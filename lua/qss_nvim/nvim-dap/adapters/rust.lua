dap = require('dap')

local execute = require('qss_nvim.utils.init').execute_and_capture_output

local mason_path = vim.fn.glob(vim.fn.stdpath("data") .. "lvim/mason/")
dap.configurations.rust = {
    {
        name = "Launch default executable",
        type = "codelldb",
        request = "launch",
        program = function()
            --local pfile = io.popen('find target/debug -name (basename (pwd))')
            local output = execute('find target/debug -name $(basename $(pwd))')
            print(output)
            --find target/debug -name (basename (pwd))
            --return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
            return output --return "/tmp/toto"
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
