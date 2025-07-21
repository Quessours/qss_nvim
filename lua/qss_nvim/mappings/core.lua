local random_shit = function()
    local ns = vim.api.nvim_create_namespace("lspEndhints")
    local bufnr = vim.api.nvim_get_current_buf()

    vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
        virt_text = { { "toto", "LspInlayHint" } },
        virt_text_pos = "eol",
        hl_mode = "combine", -- ensures highlights are combined with the background, see #2
        strict = false,      -- prevents error on quick buffer changes (e.g. quick series of undos)
        --priority = config.extmark.priority,
    })
end


M = {
    n = {
        ["<leader>af"] = { vim.lsp.buf.format, "Autoformat" },
        ["gb"] = { "<C-O>", "Go back" },
        ["<C-d>"] = { "<C-d>zz" },
        ["<C-u>"] = { "<C-u>zz" },
        ["n"] = { "nzzzv" },
        ["N"] = { "Nzzzv" },
        ["<leader>EN"] = {
            random_shit, "random_shit"
        }
    }
}

return M
