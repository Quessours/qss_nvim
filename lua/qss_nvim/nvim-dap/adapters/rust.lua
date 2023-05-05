dap = require('dap')


local mason_path = vim.fn.glob(vim.fn.stdpath("data") .. "lvim/mason/")
--[[
local codelldb_adapter = {
    type = "server",
    port = "${port}",
    executable = {
        command = mason_path .. "bin/codelldb",
        args = { "--port", "${port}" },
    },
}

dap.adapters.codelldb = codelldb_adapter
--]]
dap.configurations.rust = {
    {
        name = "Launch default executable",
        type = "codelldb",
        request = "launch",
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
    },
    {
        name = "Launch an executable",
        type = "codelldb",
        request = "launch",
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
    },
}


require("qss_nvim.nvim-dap.default_mappings")
