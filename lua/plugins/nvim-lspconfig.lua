return {
    "neovim/nvim-lspconfig",
    dependencies = {
        -- LSP Support
        {
            -- Optional
            'williamboman/mason.nvim',
            build = function()
                pcall(vim.cmd, 'MasonUpdate')
            end,
        },
        { 'williamboman/mason-lspconfig.nvim' }, -- Optional

    },
    config = function()
        require('qss_nvim.nvim-lspconfig')
        vim.lsp.inlay_hint.enable(true)
    end,
    init_options = {
        userLanguages = {
            eelixir = "html-eex",
            eruby = "erb",
            rust = "html",
        },
    }
}
