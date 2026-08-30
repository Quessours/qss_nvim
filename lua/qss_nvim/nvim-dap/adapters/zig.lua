local dap = require("dap")

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
