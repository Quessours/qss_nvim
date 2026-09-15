local opts = require("qss_nvim.rustacean-nvim.settings")

return {
    'mrcjkb/rustaceanvim',
    version = '^6', -- Recommended
    lazy = false,   -- This plugin is already lazy
    init = function()
        vim.g.rustaceanvim = opts
    end,
}
