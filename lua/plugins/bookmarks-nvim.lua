return {
    'crusj/bookmarks.nvim',
    branch = 'main',
    dependencies = { 'nvim-tree/nvim-web-devicons', 'nvim-telescope/telescope.nvim',
    },
    config = function()
        config = require("qss_nvim.bookmarks-nvim")
        require("bookmarks").setup(config)
    end
}
