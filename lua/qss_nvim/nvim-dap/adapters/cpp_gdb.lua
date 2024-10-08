dap = require('dap')
dap.adapters.cppdbg = {
    name = 'cppdbg',
    type = 'executable',
    command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}

--[[
dap.configurations.cpp = {
	{
		name = 'Debug Program',
		type = 'cppdbg',
		request = 'launch',
		MIMode = 'gdb',
		cwd = '${workspaceFolder}',
		-- udb='live',
		-- miDebuggerPath = 'udb',
		setupCommands = {
			{
				description = "Enable pretty-printing for gdb",
				text = "-enable-pretty-printing",
				ignoreFailures = true,
			}
		},
		stopAtEntry = true,
		program = 'main',
	},
}
--]]
-- TODO : Need to call cp cppdbg.ad7Engine.json nvim-dap.ad7Engine.json in
-- ~/.local/share/nvim/mason/packages/cpptools/extension/debugAdapters/bin
-- Have to automatize that ?
dap.configurations.cpp = {
    {
        name = "Launch gdbserver",
        type = "cppdbg",
        request = "launch",
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        debugServerPath = "/usr/bin/gdbserver",
        debugServerArgs = { "localhost:1234", "--no-startup-with-shell" },
        stopAtEntry = true,
    },
    --[[
    {
        name = 'Attach to gdbserver :1234',
        type = 'cppdbg',
        request = 'attach',
        target = 'localhost:1234',
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}'
    },--]]
    {
        name = 'Attach to gdbserver :1234',
        type = 'cppdbg',
        request = 'attach',
        MIMode = 'gdb',
        miDebuggerServerAddress = 'localhost:1234',
        miDebuggerPath = '/usr/bin/gdb',
        cwd = '${workspaceFolder}',
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
    },
}
--[[
dap.configurations.cpp = { {
    name = "C++ Launch",
    type = "cppdbg",
    request = "launch",
    program = function() return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file') end,
    cwd = '${workspaceFolder}',
    stopAtEntry = false,
    launchCompleteCommand = "exec-run",
    MIMode = "gdb",
    externalConsole = false,
    miDebuggerPath = "/usr/bin/gdb"
} }
--]]
dap.configurations.h = dap.configurations.cpp
dap.configurations.c = dap.configurations.cpp

start_c_debugger = function(args)
    local dap = require "dap"
    if args and #args > 0 then
        last_gdb_config = {
            type = "cppdbg",
            name = args[1],
            request = "launch",
            program = table.remove(args, 1),
            args = args,
            cwd = vim.fn.getcwd(),
            externalConsole = false,
            MIMode = "gdb",
            MIDebuggerPath = "/usr/bin/gdb"
        }
    end

    if not last_gdb_config then
        print('No binary to debug set! Use ":DebugC <binary> <args>" or ":DebugRust <binary> <args>"')
        return
    end

    print("Running debugger (or at least trying)")
    dap.run(last_gdb_config)
end


require("qss_nvim.nvim-dap.default_mappings")
