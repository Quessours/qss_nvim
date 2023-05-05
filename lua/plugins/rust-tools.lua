local opts = require("qss_nvim.rust-tools.config")
local apply_mappings = require("qss_nvim.utils").apply_mappings

local M = {
    "simrat39/rust-tools.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "mfussenegger/nvim-dap"
    },
    cond = function()
        local dir_content = require("qss_nvim.utils").scan_dir()

        for _, f in pairs(dir_content) do
            if f == "Cargo.toml" then
                return true
            end
        end
        return false
    end,
    init = function()
        local mappings = require("qss_nvim.rust-tools.mappings")
        assert(mappings ~= nil)
        apply_mappings(mappings)
    end,
    config = true,
    opts = opts
}

return M
