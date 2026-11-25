return {
    "neovim/nvim-lspconfig",
    config = function()
        require('qss_nvim.nvim-lspconfig')
        require('qss_nvim.nvim-lspconfig.commands')
        vim.lsp.inlay_hint.enable(true)
    end,
}
