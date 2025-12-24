local opts = require("qss_nvim.rustacean-nvim.settings")
local apply_mappings = require("qss_nvim.utils").apply_mappings

return {
    'mrcjkb/rustaceanvim',
    version = '^6', -- Recommended
    lazy = false,   -- This plugin is already lazy
    cond = function()
        local dir_content = require("qss_nvim.utils").scan_dir()

        for _, f in pairs(dir_content) do
            if f == "Cargo.toml" then
                return true
            end
        end
        return false
    end,
    config = function()
        require("rustaceanvim")
        vim.g.rustaceanvim = opts
        local mappings = require("qss_nvim.rustacean-nvim.mappings")
        assert(mappings ~= nil)
        apply_mappings(mappings)
    end,
    init = function()
    end
}
