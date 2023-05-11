dap = require('dap')

local mason_path = vim.fn.glob(vim.fn.stdpath("data") .. "lvim/mason/")

dap.configurations.rust = {
    {
        name = "Launch default executable",
        type = "codelldb",
        request = "launch",
        program = function()
            vim.fn.jobstart('cargo build')
            local execute = require('qss_nvim.utils').execute_and_capture_output
            local output = execute('find target/debug -name $(basename $(pwd))')
            print(output)
            --find target/debug -name (basename (pwd))
            --return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
            return output --return "/tmp/toto"
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        showDisassembly = "never"
    },
    {
        name = "Launch an executable",
        type = "codelldb",
        request = "launch",
        program = function()
            vim.fn.jobstart('cargo build')
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        showDisassembly = "never"
    },
}


require("qss_nvim.nvim-dap.default_mappings")
