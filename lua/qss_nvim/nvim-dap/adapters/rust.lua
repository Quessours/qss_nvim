dap = require('dap')

dap.configurations.rust = {
    {
        name = "Launch default executable",
        type = "codelldb",
        preLaunchTask = "cargo build",
        request = "launch",
        program = function()
            local execute = require('qss_nvim.utils').execute_and_capture_output
            local output = execute('find target/debug -name $(basename $(pwd))')
            return output
        end,
        cwd = "${workspaceFolder}",
        env = { RUST_BACKTRACE = "1" },
        stopOnEntry = false,
        showDisassembly = "never",
        console = 'integratedTerminal',
        sourceLanguages = { 'rust' }
    },
    {
        name = "Launch default executable with custom args",
        type = "codelldb",
        preLaunchTask = "cargo build",
        request = "launch",
        program = function()
            local execute = require('qss_nvim.utils').execute_and_capture_output
            local output = execute('find target/debug -name $(basename $(pwd))')
            return output
        end,
        args = function()
            local arguments = vim.fn.input('Arguments: ')
            local split_arguments = {}
            for arg in string.gmatch(arguments, "%a+") do
                table.insert(split_arguments, arg)
            end

            return split_arguments
        end,
        cwd = "${workspaceFolder}",
        env = { RUST_BACKTRACE = "1" },
        stopOnEntry = false,
        showDisassembly = "never",
        console = 'integratedTerminal',
        sourceLanguages = { "rust" }
    },
    {
        name = "Launch an executable",
        type = "codelldb",
        preLaunchTask = "cargo build",
        request = "launch",
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = "${workspaceFolder}",
        env = { RUST_BACKTRACE = "1" },
        stopOnEntry = false,
        showDisassembly = "never",
        console = 'integratedTerminal',
        sourceLanguages = { "rust" }
    },
}


require("qss_nvim.nvim-dap.default_mappings")
