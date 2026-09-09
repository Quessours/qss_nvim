local names = require('qss_nvim.qt-property.names')
local types = require('qss_nvim.cpp.types')

local M = {}

local join = types.join

---@class qss.qt.Member : qss.cpp.Definition
---@field kind 'getter'|'setter'|'reset'|'signal'|'member'
---@field name string the declared name, for the already-declared test
---@field section 'public'|'signals'|'private'
---@field declaration string one line, without indentation
---@field definition (fun(qualified: string): string[])?

---@param property qss.qt.Property
---@param name qss.qt.Names
---@return fun(qualified: string): string[]
local function getter_definition(property, name)
    return function(qualified)
        local signature = ('%s::%s() const'):format(qualified, name.getter)
        return {
            join(types.return_type(property.type), signature),
            '{',
            ('    return %s;'):format(name.member),
            '}',
        }
    end
end

---@param property qss.qt.Property
---@param name qss.qt.Names
---@return fun(qualified: string): string[]
local function setter_definition(property, name)
    local parameter = types.parameter(property.type, name.parameter)

    return function(qualified)
        local lines = {
            ('void %s::%s(%s)'):format(qualified, name.setter, parameter),
            '{',
        }

        if property.notify then
            local comparison
            if names.is_fuzzy(property.type) then
                comparison = ('qFuzzyCompare(%s, %s)'):format(name.member, name.parameter)
            else
                comparison = ('%s == %s'):format(name.member, name.parameter)
            end
            lines[#lines + 1] = ('    if (%s) {'):format(comparison)
            lines[#lines + 1] = '        return;'
            lines[#lines + 1] = '    }'
        end

        lines[#lines + 1] = ('    %s = %s;'):format(name.member, name.parameter)
        if property.notify then
            lines[#lines + 1] = ('    emit %s();'):format(name.signal)
        end
        lines[#lines + 1] = '}'
        return lines
    end
end

---@param property qss.qt.Property
---@param name qss.qt.Names
---@return fun(qualified: string): string[]
local function reset_definition(property, name)
    return function(qualified)
        local lines = {
            ('void %s::%s()'):format(qualified, name.reset),
            '{',
        }

        if property.write then
            lines[#lines + 1] = ('    %s({});'):format(name.setter)
        else
            lines[#lines + 1] = ('    %s = {};'):format(name.member)
            if property.notify then
                lines[#lines + 1] = ('    emit %s();'):format(name.signal)
            end
        end

        lines[#lines + 1] = '}'
        return lines
    end
end

---@param property qss.qt.Property
---@param name qss.qt.Names
---@return string
local function member_declaration(property, name)
    local initializer = types.initializer(property.type)
    local declared = name.member
    if initializer then
        declared = ('%s = %s'):format(name.member, initializer)
    end
    return join(property.type, declared .. ';')
end

--- Every member the macro asks for. The macro is the specification: a property
--- with no WRITE gets no setter, because nothing would call it.
---@param property qss.qt.Property
---@param name qss.qt.Names
---@return qss.qt.Member[]
function M.members(property, name)
    ---@type qss.qt.Member[]
    local members = {}

    if property.read then
        members[#members + 1] = {
            kind = 'getter',
            name = name.getter,
            section = 'public',
            declaration = join(types.return_type(property.type), name.getter .. '() const;'),
            definition = getter_definition(property, name),
        }
    end

    if property.write then
        members[#members + 1] = {
            kind = 'setter',
            name = name.setter,
            section = 'public',
            declaration = ('void %s(%s);'):format(
                name.setter, types.parameter(property.type, name.parameter)),
            definition = setter_definition(property, name),
        }
    end

    if property.reset then
        members[#members + 1] = {
            kind = 'reset',
            name = name.reset,
            section = 'public',
            declaration = ('void %s();'):format(name.reset),
            definition = reset_definition(property, name),
        }
    end

    if property.notify then
        members[#members + 1] = {
            kind = 'signal',
            name = name.signal,
            section = 'signals',
            declaration = ('void %s();'):format(name.signal),
        }
    end

    members[#members + 1] = {
        kind = 'member',
        name = name.member,
        section = 'private',
        declaration = member_declaration(property, name),
    }

    return members
end

return M
