M = {
    n = {
        ["<leader>gco"] = { "<cmd> GitConflictChooseOurs <CR>", "Choose our diff for conflict" },
        ["<leader>gct"] = { "<cmd> GitConflictChooseTheirs <CR>", "Choose their diff for conflict" },
        ["<leader>gcb"] = { "<cmd> GitConflictChooseBoth <CR>", "Choose both diffs for conflict" },
        ["<leader>gcn"] = { "<cmd> GitConflictChooseNone <CR>", "Choose none diff for conflict" },
        ["<leader>gcN"] = { "<cmd> GitConflictNextConflict <CR>", "Switch to next conflict" },
        ["<leader>gcP"] = { "<cmd> GitConflictPrevConflict <CR>", "Switch to previous conflict" }
    }
}

return M
