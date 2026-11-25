-- The `:Octo` action picker lists `review open`, which resumes the pending
-- review or starts one. The picker hides `review start` and `review resume`,
-- because `review open` does the work of both. The commands
-- `:Octo review start` and `:Octo review resume` still work when typed.
--
-- setup() wraps the `actions` function of octo.picker. The wrapper removes the
-- hidden actions from the list before the picker shows the list.
local M = {}

local hidden = {
    review = { start = true, resume = true },
}

function M.setup()
    local picker = require('octo.picker')
    local original = picker.actions
    picker.actions = function(flattened_actions)
        local shown = vim.tbl_filter(function(action)
            local hidden_names = hidden[action.object]
            return not (hidden_names and hidden_names[action.name])
        end, flattened_actions)
        return original(shown)
    end
end

return M
