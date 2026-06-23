return {
    'hrsh7th/nvim-cmp',
    dependencies = {
        { 'hrsh7th/cmp-nvim-lsp' },
        { 'hrsh7th/cmp-path' },
        { 'hrsh7th/cmp-buffer' },
        {
            'L3MON4D3/LuaSnip',
            version = 'v2.*',
            build = 'make install_jsregexp'
        },
        { 'rafamadriz/friendly-snippets' },
        { 'windwp/nvim-autopairs' },
    },
    config = function()
        require('qss_nvim.nvim-cmp')
    end,
}
