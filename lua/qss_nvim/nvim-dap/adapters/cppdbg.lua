-- The adapter that drives gdb, for a session on another machine.
--
-- codelldb covers the host: it is what dap.configurations.cpp is built around
-- in cpp_lldb.lua, and it debugs what was compiled here. A cross target is the
-- other case. The SDK ships the gdb that reads its binaries, gdbserver runs on
-- the device, and cppdbg is the adapter that speaks to that pair.
--
-- No configuration is registered here. A remote one is only meaningful with a
-- device to point it at, so deploy.lua builds it from the device table and
-- hands it to dap.run.

require('dap').adapters.cppdbg = {
    name = 'cppdbg',
    type = 'executable',
    command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}
