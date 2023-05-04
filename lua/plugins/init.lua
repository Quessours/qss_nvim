return {
    {
        'nvim-lua/plenary.nvim',
        lazy = false
    },
    "nvim-treesitter/nvim-treesitter",
    {
        dir = "/home/maxime/15_nvim_tests/02_dummy_plugin",
        init = function() print("loading toto") end,
        dependencies = {
            "nvim-lua/plenary.nvim"
        }
    }
}
