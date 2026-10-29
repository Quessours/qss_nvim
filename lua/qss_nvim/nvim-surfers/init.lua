local plugins = {
    {
        'fpeterek/nvim-surfers',
        config = function()
            require('nvim-surfers').setup({
                use_tmux = true,
            })
        end
    },
}

require("lazy").setup(plugins)
