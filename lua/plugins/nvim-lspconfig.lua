return {
    "neovim/nvim-lspconfig",
    config = function()
        require('qss_nvim.nvim-lspconfig')
        vim.lsp.inlay_hint.enable(true)
    end,
}
