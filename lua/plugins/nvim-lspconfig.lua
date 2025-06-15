return {
    "neovim/nvim-lspconfig",
    dependencies = {
        -- LSP Support
        { 'neovim/nvim-lspconfig' }, -- Required
        {
            -- Optional
            'williamboman/mason.nvim',
            build = function()
                pcall(vim.cmd, 'MasonUpdate')
            end,
        },
        { 'williamboman/mason-lspconfig.nvim' }, -- Optional

        -- Autocompletion
        { 'hrsh7th/nvim-cmp' },     -- Required
        { 'hrsh7th/cmp-nvim-lsp' }, -- Required
        { 'L3MON4D3/LuaSnip' },     -- Required
        {
            "L3MON4D3/LuaSnip",
            -- follow latest release.
            version = "v2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
            -- install jsregexp (optional!).
            build = "make install_jsregexp"
        },
        { 'rafamadriz/friendly-snippets' },
    },
    config = function()
        --local lspconfig = require('lspconfig')
        --local lsp_configs = require("qss_nvim.lsp_settings")
        --lspconfig.lua_ls.setup(lsp_configs.lua_ls)
        require('qss_nvim.nvim-lspconfig')
    end
}
