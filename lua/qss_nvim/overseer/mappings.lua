-- The language-agnostic pair: the task picker, and the list a running task is
-- watched in.
local M = {
    n = {
        ["<leader>mm"] = { "<cmd> OverseerRun <CR>", "Run a task" },
        ["<leader>mo"] = { "<cmd> OverseerToggle <CR>", "Toggle task list" },
        -- The quickfix list is made from the diagnostics of the last build, so
        -- the list and the signs in the files never disagree.
        ["<leader>mq"] = { function()
            local ns = vim.api.nvim_get_namespaces()['qss_build_diagnostics']
            if not ns then
                vim.notify('No build ran yet', vim.log.levels.INFO)
                return
            end
            vim.diagnostic.setqflist({ namespace = ns, title = 'Build errors' })
        end, "Build errors to quickfix" },
    }
}

return M
