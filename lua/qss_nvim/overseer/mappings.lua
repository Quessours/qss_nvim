-- The language-agnostic pair: the task picker, and the list a running task is
-- watched in.
local M = {
    n = {
        ["<leader>mm"] = { "<cmd> OverseerRun <CR>", "Run a task" },
        ["<leader>mo"] = { "<cmd> OverseerToggle <CR>", "Toggle task list" },
        ["<leader>mq"] = { function()
            require('qssoverseer.diagnostics').to_quickfix()
        end, "Build errors to quickfix" },
    }
}

return M
