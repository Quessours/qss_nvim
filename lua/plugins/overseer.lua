return {
    'stevearc/overseer.nvim',
    opts = {},
    init = function()
        require('overseer').setup({})
        require("qss_nvim.overseer")
    end
}
