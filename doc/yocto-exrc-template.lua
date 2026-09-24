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

-- The device the build is deployed to. :CMakeDeploy builds, installs into a
-- staging tree and copies that tree here with rsync. :CMakeRunRemote runs the
-- launch target there, and :CMakeDebugRemote starts gdbserver there and attaches
-- the cross gdb below. The two substitutions are what let that gdb find the
-- sources the build recorded under container paths.
--
-- `host` is the address, an IP or a hostname, and the login user defaults to
-- root, which is the account a Yocto image offers. A device that already has a
-- Host block in ~/.ssh/config takes `ssh = '<alias>'` instead of `host`, and
-- then that one file answers for the address, the user, the port and the key.
--
-- Keys: <leader>mh picks the device, <leader>mu deploys, <leader>mr runs,
-- <leader>md debugs. :CMakeDeployDoctor reports what is still missing.
vim.g.qss_devices = {
    {
        name = 'target',
        host = '192.168.1.42',

        -- The defaults, and the fields for the cases they miss:
        -- user = 'root',
        -- ssh_port = 22,           -- the login port, not the gdbserver one
        -- key = '~/.ssh/id_dev',   -- when the device asks for a key
        -- ssh_options = { '-o', 'ServerAliveInterval=30' },
        -- rsync_options = { '--exclude', '*.qmlc' },  -- appended, last wins
        -- ssh = 'yocto-target',    -- instead of host: a ~/.ssh/config alias

        -- Where the files land, and what the project is configured with. Keep
        -- CMAKE_INSTALL_PREFIX equal to this: <leader>mv edits it.
        prefix = '/home/root/app',

        env = { QT_QPA_PLATFORM = 'eglfs' },

        -- Shell commands for the device, in its own shell. The deploy ones run
        -- after the install and before the copy, because rsync cannot replace
        -- the file of a running binary. A command that fails does not stop the
        -- deploy.
        before_deploy = { 'systemctl stop myapp' },
        before_run = { 'pkill -f myapp' },

        gdb = sdk ..
            '/sysroots/x86_64-pokysdk-linux/usr/bin/aarch64-poky-linux/aarch64-poky-linux-gdb',
        sysroot = sysroot,
        source_map = { ['/work'] = root, ['/build'] = build },
    },
}
