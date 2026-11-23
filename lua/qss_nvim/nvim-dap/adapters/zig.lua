local build_first = require("qssoverseer.build_first")
local dap = require("dap")

dap.adapters.cppdbg = {
    name = 'cppdbg',
    type = 'executable',
    command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}

-- `zig build` installs into ./zig-out/bin, under the name of the project
-- directory by convention.
local build_and_launch = build_first.program({
    title = "Zig debug",
    build = function()
        return {
            name = "zig build (before debug)",
            cmd = { "zig", "build" },
            cwd = vim.fn.getcwd(),
            failure = "the build failed, so nothing was launched",
            title = "Zig debug",
        }
    end,
    program = function()
        local cwd = vim.fn.getcwd()
        local path = vim.fs.joinpath(cwd, "zig-out", "bin", vim.fs.basename(cwd))
        if vim.fn.executable(path) == 1 then
            return path
        end
        return nil, ("zig build produced no %s"):format(path)
    end,
})

dap.configurations.zig = {
    {
        name = "(gdb) Launch",
        type = "cppdbg",
        request = "launch",
        program = build_and_launch,
        args = {},
        stopAtEntry = false,
        cwd = "${workspaceFolder}",
        environment = {},
        externalConsole = false,
        MIMode = "gdb",
        setupCommands = {
            {
                description = "Enable pretty-printing for gdb",
                text = "-enable-pretty-printing",
                ignoreFailures = true
            }
        }
    }
}
