-- The language-agnostic pair: the task picker, and the list a running task is
-- watched in.
M = {
    n = {
        ["<leader>mm"] = { "<cmd> OverseerRun <CR>", "Run a task" },
        ["<leader>mo"] = { "<cmd> OverseerToggle <CR>", "Toggle task list" },
    }
}

return M
