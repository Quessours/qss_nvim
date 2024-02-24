return {
    'nvim-tree/nvim-web-devicons',
    config = function()
        local module = require("qss_nvim.nvim-web-devicons")
        module.setup()
    end,
    lazy = true
}
