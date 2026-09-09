local edit = require('qss_nvim.cpp.edit')
local header = require('qss_nvim.qt-property.header')
local macro = require('qss_nvim.qt-property.macro')
local names = require('qss_nvim.qt-property.names')
local source = require('qss_nvim.cpp.source')
local structure = require('qss_nvim.cpp.structure')
local templates = require('qss_nvim.qt-property.templates')
local text = require('qss_nvim.cpp.text')

local M = {}

local TITLE = 'Qt property'

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- What is missing from the class, and what is already there.
---@param members qss.qt.Member[]
---@param declared table<string, true>
---@return qss.qt.Member[] missing, string[] present
local function split_by_presence(members, declared)
    local missing, present = {}, {}
    for _, member in ipairs(members) do
        if declared[member.name] then
            present[#present + 1] = member.name
        else
            missing[#missing + 1] = member
        end
    end
    return missing, present
end

---@param members qss.qt.Member[]
---@return string
local function kinds_of(members)
    local kinds = {}
    for _, member in ipairs(members) do
        kinds[#kinds + 1] = member.kind
    end
    return table.concat(kinds, ', ')
end

--- Everything the class already promises for one property.
---@param bufnr integer
---@param row integer 0-based
---@return boolean started
function M.run(bufnr, row)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local properties, problems = macro.scan(lines)

    local property = macro.at_row(properties, row)
    if not property then
        for _, problem in ipairs(problems) do
            if row >= problem.first and row <= problem.last then
                notify(('%s\n  %s'):format(problem.text, problem.reason), vim.log.levels.ERROR)
                return false
            end
        end
        notify('no Q_PROPERTY on this line', vim.log.levels.WARN)
        return false
    end

    local reason = macro.validate(property)
    if reason then
        notify(('%s\n  %s'):format(property.text, reason), vim.log.levels.ERROR)
        return false
    end

    local class, class_reason = structure.class_at(bufnr, property.first)
    if not class then
        notify(class_reason or 'the class could not be read', vim.log.levels.ERROR)
        return false
    end
    if class.one_line then
        notify(('%s is written on one line; its members must be added by hand')
            :format(class.name), vim.log.levels.ERROR)
        return false
    end

    local name, name_reason = names.of(property)
    if not name then
        notify(('%s\n  %s'):format(property.text, name_reason), vim.log.levels.ERROR)
        return false
    end

    local missing, present = split_by_presence(templates.members(property, name), class.declared)

    local report = { ('%s::%s'):format(class.name, property.name) }
    if #present > 0 then
        report[#report + 1] = ('  already declared: %s'):format(table.concat(present, ', '))
    end

    if #missing == 0 then
        report[#report + 1] = '  nothing to add'
        notify(table.concat(report, '\n'), vim.log.levels.INFO)
        return true
    end

    local code = text.code_lines(lines)
    edit.apply(bufnr, header.plan(bufnr, class, missing, code))

    local header_line = ('  header: %s'):format(kinds_of(missing))
    if vim.bo[bufnr].modified then
        header_line = header_line .. ' (buffer not saved yet)'
    end
    report[#report + 1] = header_line

    if not class.has_q_object then
        report[#report + 1] = ('  %s has no Q_OBJECT macro'):format(class.name)
    end
    if names.is_fuzzy(property.type) then
        report[#report + 1] = '  qFuzzyCompare needs <QtGlobal>'
    end

    local definable = {}
    for _, member in ipairs(missing) do
        if member.definition then
            definable[#definable + 1] = member
        end
    end

    local function finish()
        notify(table.concat(report, '\n'), vim.log.levels.INFO)
    end

    if #definable == 0 then
        finish()
        return true
    end
    if class.templated then
        report[#report + 1] = ('  %s is a template; its definitions belong in the header')
            :format(class.name)
        finish()
        return true
    end
    if class.anonymous_namespace then
        report[#report + 1] = ('  %s is in an anonymous namespace'):format(class.name)
        finish()
        return true
    end

    source.find(bufnr, function(path)
        if not path then
            report[#report + 1] = '  no implementation file found; only the header was changed'
            return finish()
        end

        local written, write_reason = source.write(path, class.qualified, definable)
        local shown = vim.fn.fnamemodify(path, ':t')
        if write_reason then
            report[#report + 1] = ('  %s'):format(write_reason)
        elseif written > 0 then
            report[#report + 1] = ('  %s: %d definitions'):format(shown, written)
        else
            report[#report + 1] = ('  %s: already defined'):format(shown)
        end
        finish()
    end)

    return true
end

return M
