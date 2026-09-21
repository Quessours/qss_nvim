-- A template for the `.nvim.lua` of a Yocto project root. Copy it there, fill
-- in the three paths, and nothing in this config has to know about Yocto:
-- init.lua sets `exrc`, so Neovim reads that file when it starts in that tree,
-- and only then.
--
-- Both settings below are needed because a kas-container build happens
-- somewhere else. The compiler runs inside the container, so every path it
-- records in compile_commands.json, and every path the debugger reads out of
-- the binary, is a container path: /work for the checkout, /build for the build
-- directory. Neither exists on this machine.

local root = vim.fn.getcwd()
local build = root .. '/build'

-- The cross toolchain of the SDK. `--query-driver` is what lets clangd ask that
-- compiler for its own include paths, instead of handing the target sources the
-- host headers and reporting errors that are not there.
local sdk = vim.fn.expand('~/opt/poky-sdk')
local driver = sdk .. '/sysroots/x86_64-pokysdk-linux/usr/bin/*/*-poky-linux-*gcc'

-- The sysroot the target binaries were built against, for the debugger.
local sysroot = sdk .. '/sysroots/cortexa72-poky-linux'

vim.lsp.config('clangd', {
    cmd = {
        'clangd',
        ('--path-mappings=/work=%s,/build=%s'):format(root, build),
        ('--query-driver=%s'):format(driver),
        -- Uncomment when the compilation database is not symlinked into the
        -- source tree:
        -- ('--compile-commands-dir=%s'):format(build .. '/tmp/work/<machine>/<recipe>/<version>/build'),
    },
})

-- A clangd that is already running keeps the old command. :LspRestart clangd
-- picks this up in a session that was started before the file existed.

-- Debugging on the target: gdbserver runs there, the cross gdb runs here, and
-- the two path substitutions are what let it find the sources and the libraries
-- that the build put under container paths.
vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'c', 'cpp' },
    once = true,
    desc = 'Add the on-target debug configuration',
    callback = function()
        local ok, dap = pcall(require, 'dap')
        if not ok then
            return
        end

        table.insert(dap.configurations.cpp, {
            name = 'Attach to gdbserver on the target',
            type = 'cppdbg',
            request = 'launch',
            MIMode = 'gdb',
            miDebuggerPath = sdk ..
                '/sysroots/x86_64-pokysdk-linux/usr/bin/aarch64-poky-linux/aarch64-poky-linux-gdb',
            miDebuggerServerAddress = '192.168.1.10:1234',
            program = function()
                return vim.fn.input('Path to the host copy of the binary: ', build .. '/', 'file')
            end,
            cwd = root,
            stopAtEntry = false,
            setupCommands = {
                {
                    description = 'Look up shared libraries in the SDK sysroot',
                    text = ('set sysroot %s'):format(sysroot),
                    ignoreFailures = false,
                },
                {
                    description = 'Map the container source paths to this machine',
                    text = ('set substitute-path /build %s'):format(build),
                    ignoreFailures = false,
                },
                {
                    description = 'Map the container checkout paths to this machine',
                    text = ('set substitute-path /work %s'):format(root),
                    ignoreFailures = false,
                },
                {
                    description = 'Enable pretty printing',
                    text = '-enable-pretty-printing',
                    ignoreFailures = true,
                },
            },
        })
    end,
})
