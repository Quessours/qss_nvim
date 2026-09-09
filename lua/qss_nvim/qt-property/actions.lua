local macro = require('qss_nvim.qt-property.macro')
local names = require('qss_nvim.qt-property.names')
local structure = require('qss_nvim.cpp.structure')
local templates = require('qss_nvim.qt-property.templates')

local M = {}

M.COMMAND = 'qtprops.generate'

--- The members the class does not declare yet.
---@param property qss.qt.Property
---@param declared table<string, true>
---@return qss.qt.Member[]
local function missing_members(property, declared)
    local name = names.of(property)
    if not name then
        return {}
    end

    local missing = {}
    for _, member in ipairs(templates.members(property, name)) do
        if not declared[member.name] then
            missing[#missing + 1] = member
        end
    end
    return missing
end

--- One action per property overlapping the range. A property with nothing
--- missing offers none.
---@param bufnr integer
---@param range lsp.Range
---@param uri string
---@return lsp.CodeAction[]
function M.at(bufnr, range, uri)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local properties = macro.scan(lines)
    if #properties == 0 then
        return {}
    end

    local from, to = range.start.line, range['end'].line
    local actions = {}

    for _, property in ipairs(properties) do
        local overlaps = property.first <= to and property.last >= from
        if overlaps and not macro.validate(property) then
            local class = structure.class_at(bufnr, property.first)
            if class and not class.one_line then
                local missing = missing_members(property, class.declared)
                if #missing > 0 then
                    local kinds = {}
                    for _, member in ipairs(missing) do
                        kinds[#kinds + 1] = member.kind
                    end
                    actions[#actions + 1] = {
                        title = ("Q_PROPERTY: generate %s for '%s'")
                            :format(table.concat(kinds, ', '), property.name),
                        kind = 'refactor.rewrite',
                        command = {
                            title = 'Generate Q_PROPERTY members',
                            command = M.COMMAND,
                            arguments = { uri, property.first },
                        },
                    }
                end
            end
        end
    end

    return actions
end

return M
