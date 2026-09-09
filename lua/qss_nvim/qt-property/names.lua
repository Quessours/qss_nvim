local types = require('qss_nvim.cpp.types')

local M = {}

--- Types compared with qFuzzyCompare rather than ==.
local FUZZY = { ['float'] = true, ['double'] = true, ['long double'] = true, ['qreal'] = true }

---@param word string
---@return string
function M.capitalize(word)
    return word:sub(1, 1):upper() .. word:sub(2)
end

---@param written string
---@return boolean
function M.is_fuzzy(written)
    return FUZZY[types.bare(written)] == true
end

---@class qss.qt.Names
---@field base string the property name without its member prefix
---@field getter string
---@field setter string
---@field signal string
---@field reset string
---@field member string
---@field parameter string the setter's parameter name

--- Every name the property implies.
---@param property qss.qt.Property
---@return qss.qt.Names? names, string? reason
function M.of(property)
    if not property.name then
        return nil, 'needs a type and a name'
    end

    local base = property.name:gsub('^m_', ''):gsub('^_', '')
    if base == '' then
        return nil, ('%s is not a valid property name'):format(property.name)
    end

    local member = property.member or ('m_' .. base)
    local parameter = base
    if parameter == member or types.is_keyword(parameter) then
        parameter = 'new' .. M.capitalize(base)
    end

    return {
        base = base,
        getter = property.read or base,
        setter = property.write or ('set' .. M.capitalize(base)),
        signal = property.notify or (base .. 'Changed'),
        reset = property.reset or ('reset' .. M.capitalize(base)),
        member = member,
        parameter = parameter,
    }, nil
end

return M
