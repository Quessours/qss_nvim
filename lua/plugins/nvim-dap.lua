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
    config = function()
        require('qss_nvim.nvim-dap').setup()
    end
}

--is_cargo_toml_present()

return M
