local opts = require("qss_nvim.rustacean-nvim.settings")
local apply_mappings = require("qss_nvim.utils").apply_mappings

return {
    'mrcjkb/rustaceanvim',
    version = '^6', -- Recommended
    lazy = false,   -- This plugin is already lazy
    config = function()
        --require("rustaceanvim").setup(opts)
        vim.g.rustaceanvim = opts
        local mappings = require("qss_nvim.rustacean-nvim.mappings")
        assert(mappings ~= nil)
        apply_mappings(mappings)
    end
}
