local opts = require("qss_nvim.rustacean-nvim.settings")

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
    end
}
