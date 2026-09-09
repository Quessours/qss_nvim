local structure = require('qss_nvim.cpp.structure')

local M = {}

--- The name a definition writes, with the namespaces it sits in put back in
--- front of it. A definition inside a reopened namespace block and one written
--- fully qualified then read the same.
---@param definition qss.cpp.Defined
---@return string
local function full_name(definition)
    local segments = vim.list_extend({}, definition.namespaces)
    vim.list_extend(segments, vim.split(definition.qualified, '::', { plain = true }))
    return table.concat(segments, '::')
end

--- A scope with the namespaces already open around it taken off the front.
---@param scope string
---@param namespaces string[]
---@return string
local function relative(scope, namespaces)
    if scope == '' then
        return ''
    end

    local segments = vim.split(scope, '::', { plain = true })
    local at = 1
    while at <= #segments and segments[at] == namespaces[at] do
        at = at + 1
    end
    return table.concat(vim.list_slice(segments, at), '::')
end

---@param lines string[]
---@return qss.cpp.Defined[]
function M.definitions(lines)
    return structure.definitions(table.concat(lines, '\n'))
end

---@class qss.cpp.impl.Spot
---@field row integer 0-based row to insert in front of
---@field scope string the qualification to write at that row
---@field separate boolean true when the row above it holds code
---@field defined integer? the row an existing definition starts on

--- Where the definition of `scope::name` belongs.
---@param definitions qss.cpp.Defined[]
---@param lines string[]
---@param scope string
---@param name string
---@return qss.cpp.impl.Spot
function M.spot(definitions, lines, scope, name)
    local wanted = name
    if scope ~= '' then
        wanted = ('%s::%s'):format(scope, name)
    end

    ---@type qss.cpp.Defined?
    local last_of_scope

    for _, definition in ipairs(definitions) do
        local full = full_name(definition)
        if full == wanted then
            return { row = definition.first, scope = scope, separate = false, defined = definition.first }
        end

        local segments = vim.split(full, '::', { plain = true })
        local owner = table.concat(vim.list_slice(segments, 1, #segments - 1), '::')
        if owner == scope then
            last_of_scope = definition
        end
    end

    local row = #lines
    local namespaces = {}
    if last_of_scope then
        row = last_of_scope.last + 1
        namespaces = last_of_scope.namespaces
    end

    local above = lines[row]
    return {
        row = row,
        scope = relative(scope, namespaces),
        separate = above ~= nil and vim.trim(above) ~= '',
        defined = nil,
    }
end

return M
