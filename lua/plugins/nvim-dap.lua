--[[local function is_cargo_toml_present()
    local scan = require("plenary.scan")
    local cwd = vim.fn.getcwd()
end
--]]
local M = {
    'mfussenegger/nvim-dap',
    event = "BufReadPre",
    dependencies = {
        "theHamsta/nvim-dap-virtual-text",
        "rcarriga/nvim-dap-ui",
        "nvim-telescope/telescope-dap.nvim",
        "jbyuki/one-small-step-for-vimkind",
        "mfussenegger/nvim-dap-python",
    },
    --[[
    enabled = function()
        local dir_content = require("qss_nvim.utils").scan_dir()

        for _, f in pairs(dir_content) do
            if f == "Cargo.toml" then
                return false
            end
        end
        return true
    end,
    --]]
    config = function()
        require('qss_nvim.nvim-dap').setup()
    end
}

--is_cargo_toml_present()

return M
