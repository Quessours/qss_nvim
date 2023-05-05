local opts = require("qss_nvim.rust-tools.config")

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
    init = function() require("qss_nvim.rust-tools.mappings") end,
    config = true,
    opts = opts
}

return M
