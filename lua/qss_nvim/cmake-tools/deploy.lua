-- Build, install into a staging tree, copy it to the device, run it there.
--
-- This is what Qt Creator's deploy step does, in the same order and for the
-- same reason. The install rules of the project are the only description of
-- which files the program needs at runtime, so the staging tree is built by
-- cmake and not by a list of files kept here. DESTDIR is what makes that tree
-- mirror the device: the binary is configured with the prefix it will run
-- under, and DESTDIR only decides where that layout is assembled on this
-- machine.
--
-- Every entry point goes through act(): it checks the device once, and then
-- hands that device down the chain as an argument.

local build = require('qss_nvim.cmake-tools.build')
local build_first = require('qss_nvim.overseer.build_first')
local devices = require('qss_nvim.remote.device')
local findings = require('qss_nvim.findings')
local remote_doctor = require('qss_nvim.remote.doctor')
local state = require('qss_nvim.cmake-tools.state')
local strategy = require('qss_nvim.overseer.strategy')

local M = {}

local TITLE = 'Deploy'

--- The last step, whose output is the answer.
local FINAL_COMPONENTS = {
    'on_exit_set_status',
    'on_complete_notify',
    { 'on_complete_dispose', require_view = { 'SUCCESS', 'FAILURE' } },
}

--- DESTDIR and rsync both need a path that means the same thing from anywhere,
--- and cmake-tools hands back the build directory relative to the project.
---@return string
local function build_dir()
    local absolute = vim.fs.normalize(vim.fn.fnamemodify(state.build_dir(), ':p'))
    return (absolute:gsub('/+$', ''))
end

--- Where the install step assembles the tree for this device.
---@param device qss.remote.Device
---@return string
function M.staging(device)
    return ('%s/qss-deploy/%s'):format(build_dir(), device.name)
end

--- The directory inside the staging tree that matches the root of the device.
--- With DESTDIR set, cmake writes to DESTDIR followed by the install prefix.
---@param device qss.remote.Device
---@return string
function M.staged_root(device)
    return M.staging(device) .. device.prefix
end

--- The binary on this machine, which is the one that still carries its symbols.
---@return string? path
---@return string? message why there is none
local function host_binary()
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    if not ok then
        return nil, 'cmake-tools.nvim is not loaded'
    end

    local result = cmake_tools.get_config():get_launch_target()
    if result.code ~= 0 then
        return nil, result.message
    end
    return result.data
end

--- The same program, on the device.
---
--- The install rules decide where under the prefix it lands, and reading them
--- back means reading the CMake file API. The staged tree already answers it:
--- the file is in there, under the path the device will see.
---@param device qss.remote.Device
---@return string? path
---@return string? message why there is none
function M.remote_binary(device)
    local host_path, message = host_binary()
    if not host_path then
        return nil, message
    end

    local name = vim.fs.basename(host_path)
    local root = M.staged_root(device)
    local staged = vim.fs.find(name, { path = root, type = 'file', limit = 1 })[1]
    if not staged then
        return nil, ('%s was not installed into %s'):format(name, root)
    end
    return device.prefix .. staged:sub(#root + 1)
end

--- One task of the chain. It stays quiet when it works, and opens its log and
--- stops the chain when it fails, the same way the build before it does.
---@param opts qss.overseer.BuildFirst
---@param on_success fun()
local function step(opts, on_success)
    build_first.run(opts, function(ok)
        if ok then
            on_success()
        end
    end)
end

--- Run the steps one after the other. Each step calls its argument to start the
--- next one, and does not call it to stop the chain.
---@param steps fun(done: fun())[]
---@param on_success fun()
local function in_order(steps, on_success)
    local function from(index)
        if index > #steps then
            return on_success()
        end
        steps[index](function()
            from(index + 1)
        end)
    end
    from(1)
end

--- Whether the staged tree holds anything at all. A project without install()
--- rules makes `cmake --install` succeed and copy nothing, which is the one
--- failure in this chain that otherwise looks like success.
---@param device qss.remote.Device
---@return boolean
local function staged_tree_is_empty(device)
    local root = M.staged_root(device)
    if vim.fn.isdirectory(root) ~= 1 then
        return true
    end
    return vim.fs.dir(root)() == nil
end

---@param device qss.remote.Device
---@param on_success fun()
local function install(device, on_success)
    local staging = M.staging(device)

    -- What the last install left behind would be copied again, and a file that
    -- the project stopped installing would look current forever.
    if staging:find('/qss-deploy/', 1, true) then
        vim.fn.delete(staging, 'rf')
    end

    step({
        name = ('cmake install (staging for %s)'):format(device.name),
        cmd = { 'cmake', '--install', build_dir(), '--config', state.build_type() },
        env = { DESTDIR = staging },
        failure = 'the install step failed; nothing was copied',
        title = TITLE,
    }, function()
        if staged_tree_is_empty(device) then
            return findings.notify({
                {
                    level = 'error',
                    text = 'the project installs no files',
                    fix = 'install(TARGETS <target> RUNTIME DESTINATION bin) in CMakeLists.txt',
                },
            }, 'Nothing to deploy', TITLE)
        end
        on_success()
    end)
end

--- What the device has to do before the copy: stop the service, kill the old
--- instance. It comes after the build and the install on purpose, so a build
--- that fails never takes a running program down for nothing.
---
--- Replacing the file of a running binary is also the one thing rsync cannot
--- do: Linux answers ETXTBSY, and the copy fails with "Text file busy".
---@param device qss.remote.Device
---@param on_success fun()
local function prepare(device, on_success)
    local command = devices.hook_command(device.before_deploy)
    if not command then
        return on_success()
    end

    step({
        name = ('prepare %s'):format(device.name),
        cmd = devices.ssh_argv(device, command),
        failure = ('the before_deploy commands could not run on %s'):format(device.target),
        title = TITLE,
    }, on_success)
end

---@param device qss.remote.Device
---@param on_success fun()
local function copy(device, on_success)
    step({
        name = ('rsync to %s'):format(device.name),
        cmd = devices.rsync_argv(device, M.staged_root(device)),
        failure = 'the copy to the device failed',
        title = TITLE,
    }, on_success)
end

--- Build, install into the staging tree, copy it to the device.
---@param device qss.remote.Device
---@param on_success fun()?
local function deploy_to(device, on_success)
    require('overseer').open({ enter = false, direction = 'bottom' })
    vim.notify(('building for %s...'):format(device.name), vim.log.levels.INFO,
        { title = TITLE })

    in_order({
        function(done)
            build.first({
                name = 'cmake build (before deploy)',
                failure = 'build failed; nothing was deployed',
                title = TITLE,
            }, done)
        end,
        function(done) install(device, done) end,
        function(done) prepare(device, done) end,
        function(done) copy(device, done) end,
    }, function()
        vim.notify(('deployed to %s:%s'):format(device.target, device.prefix),
            vim.log.levels.INFO, { title = TITLE })
        if on_success then
            on_success()
        end
    end)
end

--- Deploy, then run the launch target on the device.
---@param device qss.remote.Device
local function run_on(device)
    deploy_to(device, function()
        -- A device that names a run_command is started through it, and not
        -- through the launch target. A launcher reads the board settings and
        -- exports the environment that the bare binary would otherwise need
        -- spelled out in `env`, one value per board. The debugger below keeps
        -- the binary, because gdbserver takes a program.
        local remote = device.run_command
        if not remote then
            local message
            remote, message = M.remote_binary(device)
            if not remote then
                return vim.notify(message, vim.log.levels.ERROR, { title = TITLE })
            end
        end

        local words = { remote }
        vim.list_extend(words, device.args)

        local overseer = require('overseer')
        local task = overseer.new_task({
            name = ('%s on %s'):format(vim.fs.basename(remote), device.name),
            cmd = devices.ssh_argv(device,
                devices.remote_command(device, words, { before = device.before_run }),
                { tty = true }),
            strategy = strategy.program,
            components = vim.deepcopy(FINAL_COMPONENTS),
        })
        overseer.open({ enter = false, direction = 'bottom' })
        task:start()
    end)
end

--- What gdbserver prints once it holds the port. Waiting for it beats waiting a
--- fixed number of seconds, which is either too short on a cold device or time
--- spent staring at nothing.
local LISTENING = 'Listening on port'

--- How long to wait for that line before saying so.
local LISTEN_TIMEOUT_MS = 30000

---@param device qss.remote.Device
---@return table[] the gdb commands that make the target binaries readable
local function setup_commands(device)
    local commands = {}

    if device.sysroot then
        commands[#commands + 1] = {
            description = 'Look up shared libraries in the SDK sysroot',
            text = ('set sysroot %s'):format(device.sysroot),
            ignoreFailures = false,
        }
    end

    local from_paths = vim.tbl_keys(device.source_map)
    table.sort(from_paths)
    for _, from in ipairs(from_paths) do
        commands[#commands + 1] = {
            description = ('Map %s to this machine'):format(from),
            text = ('set substitute-path %s %s'):format(from, device.source_map[from]),
            ignoreFailures = false,
        }
    end

    commands[#commands + 1] = {
        description = 'Enable pretty printing',
        text = '-enable-pretty-printing',
        ignoreFailures = true,
    }
    return commands
end

--- Hand the session over to nvim-dap, and take the server down with it.
---@param device qss.remote.Device
---@param server table the overseer task running gdbserver
local function attach(device, server)
    local address = devices.resolve(device)
    if not address then
        return vim.notify(('ssh cannot resolve %s'):format(device.target),
            vim.log.levels.ERROR, { title = TITLE })
    end

    local host_path = host_binary()
    local dap = require('dap')

    local function stop()
        dap.listeners.after.event_terminated['qss_deploy'] = nil
        dap.listeners.after.event_exited['qss_deploy'] = nil
        if not server:is_disposed() then
            server:stop()
            server:dispose()
        end
    end

    dap.listeners.after.event_terminated['qss_deploy'] = stop
    dap.listeners.after.event_exited['qss_deploy'] = stop

    dap.run({
        name = 'Debug on ' .. device.name,
        type = 'cppdbg',
        request = 'launch',
        MIMode = 'gdb',
        miDebuggerPath = device.gdb,
        miDebuggerServerAddress = ('%s:%d'):format(address.hostname, device.port),
        program = host_path,
        cwd = vim.fs.normalize(vim.uv.cwd() or '.'),
        stopAtEntry = false,
        setupCommands = setup_commands(device),
    })
end

--- Deploy, start gdbserver on the device, attach the cross gdb to it.
---@param device qss.remote.Device
local function debug_on(device)
    deploy_to(device, function()
        local remote, message = M.remote_binary(device)
        if not remote then
            return vim.notify(message, vim.log.levels.ERROR, { title = TITLE })
        end

        local words = { device.gdbserver, (':%d'):format(device.port), remote }
        vim.list_extend(words, device.args)

        local overseer = require('overseer')
        local server = overseer.new_task({
            name = ('gdbserver :%d on %s'):format(device.port, device.name),
            cmd = devices.ssh_argv(device,
                devices.remote_command(device, words, { before = device.before_run }),
                { tty = true }),
            strategy = strategy.program,
            components = {
                'on_exit_set_status',
                { 'on_complete_notify', statuses = { 'FAILURE' } },
            },
        })

        local listening = false
        server:subscribe('on_output_lines', function(_, lines)
            for _, line in ipairs(lines) do
                if line:find(LISTENING, 1, true) then
                    listening = true
                    vim.schedule(function()
                        attach(device, server)
                    end)
                    return true
                end
            end
        end)

        vim.notify(('starting gdbserver on %s...'):format(device.name),
            vim.log.levels.INFO, { title = TITLE })
        server:start()

        vim.defer_fn(function()
            if not listening and not server:is_disposed() then
                vim.notify(('gdbserver did not report "%s" in %d seconds')
                    :format(LISTENING, LISTEN_TIMEOUT_MS / 1000),
                    vim.log.levels.WARN, { title = TITLE })
            end
        end, LISTEN_TIMEOUT_MS)
    end)
end

---@class qss.cmake.DeployOpts
---@field force boolean? skip the checks

---@class qss.cmake.RemoteAction
---@field doctor fun(device: qss.remote.Device?): qss.Finding[] what must pass first
---@field header string what the report says when the checks block it
---@field start fun(device: qss.remote.Device)

---@type qss.cmake.RemoteAction
local DEPLOY = { doctor = remote_doctor.run, header = 'Deploy blocked', start = deploy_to }

---@type qss.cmake.RemoteAction
local RUN = { doctor = remote_doctor.run, header = 'Run blocked', start = run_on }

--- The debug checks add the cross toolchain to the deploy ones.
---@type qss.cmake.RemoteAction
local DEBUG = { doctor = remote_doctor.debug, header = 'Debug blocked', start = debug_on }

--- Check the device, then start the action on it. This is the only place that
--- checks anything before a deploy. The doctor also covers a build configured
--- for another CMAKE_INSTALL_PREFIX than the device holds, because it reports
--- that as a warning and a warning blocks.
---@param action qss.cmake.RemoteAction
---@param device qss.remote.Device?
---@param opts qss.cmake.DeployOpts?
local function act(action, device, opts)
    opts = opts or {}
    if not opts.force then
        local blocking = findings.blocking(action.doctor(device))
        if #blocking > 0 then
            return findings.notify(blocking, action.header, TITLE)
        end
    end
    if not device or not device.prefix then
        return vim.notify('no usable device is selected', vim.log.levels.ERROR,
            { title = TITLE })
    end
    action.start(device)
end

--- :CMakeDeploy
---@param opts qss.cmake.DeployOpts?
function M.deploy(opts)
    act(DEPLOY, devices.selected(), opts)
end

--- :CMakeRunRemote
---@param opts qss.cmake.DeployOpts?
function M.run(opts)
    act(RUN, devices.selected(), opts)
end

--- :CMakeDebugRemote
---@param opts qss.cmake.DeployOpts?
function M.debug(opts)
    act(DEBUG, devices.selected(), opts)
end

--- Where this build runs: here, or on the device it was configured for. A
--- cross build cannot start on this machine.
---@param action qss.cmake.RemoteAction what runs it on the device
---@param here fun() what runs it on this machine
local function wherever_it_runs(action, here)
    if not state.cross_compiling() then
        return here()
    end

    -- pick() is only reached with several devices declared: selected() answers
    -- by itself when the project declares one. It also reports the case where
    -- the project declares none.
    local device = devices.selected()
    if device then
        return act(action, device)
    end
    devices.pick(function(chosen)
        act(action, chosen)
    end)
end

--- <leader>mr: run it where it runs.
function M.run_wherever()
    wherever_it_runs(RUN, function()
        vim.cmd('CMakeRun')
    end)
end

--- <leader>md: debug it where it runs.
function M.debug_wherever()
    wherever_it_runs(DEBUG, function()
        vim.cmd('CMakeDebug')
    end)
end

return M
