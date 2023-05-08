M = {
    n = {
        ["<leader>af"] = { vim.lsp.buf.format, "focus nvimtree" },
        ["gb"] = { "<C-O>", "Go back" },
        ["<C-d>"] = { "<C-d>zz" },
        ["<C-u>"] = { "<C-u>zz" },
        ["n"] = { "nzzzv" },
        ["N"] = { "Nzzzv" }
    }
}

return M
