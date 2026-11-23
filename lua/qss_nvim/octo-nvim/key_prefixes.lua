-- The octo.nvim keys under <localleader> move to other prefixes:
--   * The review keys and the reviewer keys move from <localleader>v to
--     <localleader>r, for example <localleader>vs becomes <localleader>rs.
--   * The reaction keys, the thread keys and the "reference comment in new
--     issue" key move from <localleader>r to <localleader>t, for example
--     <localleader>rt becomes <localleader>tt.
-- The which-key group labels in qss_nvim/which-key/config.lua follow these
-- prefixes.
local M = {}

local MOVES = {
    { from = '<localleader>v', to = '<localleader>r' },
    { from = '<localleader>r', to = '<localleader>t' },
}

---@param lhs string
---@return string? moved The new key, or nil when the key does not move.
local function move(lhs)
    for _, rule in ipairs(MOVES) do
        if vim.startswith(lhs, rule.from) then
            return rule.to .. lhs:sub(#rule.from + 1)
        end
    end
    return nil
end

--- Adds the moved octo.nvim default keys to `mappings`, the mappings table of
--- the octo.nvim options. A key that `mappings` already sets for an action
--- keeps its value.
---@param mappings table<string, table<string, table>>
function M.apply(mappings)
    local defaults = require('octo.config').get_default_values().mappings
    for section, actions in pairs(defaults) do
        -- The octo spec can share one table between sections, so each section
        -- gets its own copy before the new keys go in.
        local own = vim.tbl_extend('force', {}, mappings[section] or {})
        for action, mapping in pairs(actions) do
            local moved = type(mapping) == 'table' and type(mapping.lhs) == 'string' and move(mapping.lhs)
            if moved and own[action] == nil then
                own[action] = { lhs = moved, desc = mapping.desc }
            end
        end
        mappings[section] = own
    end
end

return M
