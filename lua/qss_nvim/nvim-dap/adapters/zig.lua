local dap = require("dap")

--[[
dap.configurations.zig = {
    {
        name = "Launch default executable",
        type = "codelldb",
        request = "launch",
        program = "./zig-cache/bin/build",
        stopAtEntry = false,
        cwd = "${workspaceFolder}",
        p/homereLaunchTask = "build",
        sourceLanguages = { 'zig' }
    }
}
--]]
-- TODO : Need to call cp cppdbg.ad7Engine.json nvim-dap.ad7Engine.json in
-- ~/.local/share/nvim/mason/packages/cpptools/extension/debugAdapters/bin
-- Have to automatize that ?

dap.adapters.cppdbg = {
    name = 'cppdbg',
    type = 'executable',
    command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}

dap.configurations.zig = {
    {
        name = "(gdb) Launch",
        type = "cppdbg",
        request = "launch",
        program = "./zig-out/bin/${workspaceFolderBasename}",
        args = {},
        stopAtEntry = false,
        cwd = "${workspaceFolder}",
        environment = {},
        externalConsole = false,
        MIMode = "gdb",
        preLaunchTask = "zig build",
        setupCommands = {
            {
                description = "Enable pretty-printing for gdb",
                text = "-enable-pretty-printing",
                ignoreFailures = true
            }
        }
    }
}
