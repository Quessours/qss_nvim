-- Build, install into a staging tree, copy it to the device, run it there.
--
-- This is what Qt Creator's deploy step does, in the same order and for the
-- same reason. The install rules of the project are the only description of
-- which files the program needs at runtime, so the staging tree is built by
-- cmake and not by a list of files kept here. DESTDIR is what makes that tree
-- mirror the device: the binary is configured with the prefix it will run
-- under, and DESTDIR only decides where that layout is assembled on this
-- machine.

local build = require('qss_nvim.cmake-tools.build')
local devices = require('qss_nvim.remote.device')
local findings = require('qss_nvim.findings')
local remote_doctor = require('qss_nvim.remote.doctor')
local state = require('qss_nvim.cmake-tools.state')

local M = {}

local TITLE = 'Deploy'

--- A step the user watches the next step of. It reports only when it fails,
--- because the output worth reading is the one at the end of the chain.
local STEP_COMPONENTS = {
    'on_exit_set_status',
    { 'on_complete_notify',  statuses = { 'FAILURE' } },
    { 'on_complete_dispose', require_view = { 'FAILURE' } },
}

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

---@param definition table an overseer task definition
---@param failure string what to say when this step fails
---@param on_success fun()
---@return table task
local function step(definition, failure, on_success)
    local overseer = require('overseer')
    local task = overseer.new_task(definition)

    task:subscribe('on_complete', function(_, status)
        if status == 'SUCCESS' then
            on_success()
        else
            vim.notify(failure, vim.log.levels.ERROR, { title = TITLE })
        end
        -- A truthy return unsubscribes, which one step is done with either way.
        return true
    end)
    task:start()
    return task
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
        cmd = { 'cmake' },
        args = { '--install', build_dir(), '--config', state.build_type() },
        env = { DESTDIR = staging },
        components = vim.deepcopy(STEP_COMPONENTS),
    }, 'the install step failed; nothing was copied', on_success)
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

    local argv = devices.ssh_argv(device, command)
    step({
        name = ('prepare %s'):format(device.name),
        cmd = { argv[1] },
        args = vim.list_slice(argv, 2),
        components = vim.deepcopy(STEP_COMPONENTS),
    }, ('the before_deploy commands could not run on %s'):format(device.target), on_success)
end

---@param device qss.remote.Device
---@param on_success fun()
local function copy(device, on_success)
    local argv = devices.rsync_argv(device, M.staged_root(device))
    step({
        name = ('rsync to %s'):format(device.name),
        cmd = { argv[1] },
        args = vim.list_slice(argv, 2),
        components = vim.deepcopy(STEP_COMPONENTS),
    }, 'the copy to the device failed', on_success)
end

---@param list qss.Finding[]
---@param header string
---@return boolean
local function blocked(list, header)
    local blocking = findings.blocking(list)
    if #blocking == 0 then
        return false
    end
    findings.notify(blocking, header, TITLE)
    return true
end

---@class qss.cmake.DeployOpts
---@field force boolean? skip the checks

--- Build, install into the staging tree, copy it to the device.
---@param opts qss.cmake.DeployOpts?
---@param on_success fun(device: qss.remote.Device)?
function M.deploy(opts, on_success)
    opts = opts or {}
    local device = devices.selected()

    if not opts.force and blocked(remote_doctor.run(device), 'Deploy blocked') then
        return
    end
    if not device or not device.prefix then
        return vim.notify('no usable device is selected', vim.log.levels.ERROR,
            { title = TITLE })
    end

    require('overseer').open({ enter = false, direction = 'bottom' })
    vim.notify(('building for %s...'):format(device.name), vim.log.levels.INFO,
        { title = TITLE })

    build.first({
        label = 'cmake build (before deploy)',
        failure = 'build failed; nothing was deployed',
        title = TITLE,
    }, function()
        install(device, function()
            if staged_tree_is_empty(device) then
                return findings.notify({
                    {
                        level = 'error',
                        text = 'the project installs no files',
                        fix = 'install(TARGETS <target> RUNTIME DESTINATION bin) in CMakeLists.txt',
                    },
                }, 'Nothing to deploy', TITLE)
            end

            prepare(device, function()
                copy(device, function()
                    vim.notify(('deployed to %s:%s'):format(device.target, device.prefix),
                        vim.log.levels.INFO, { title = TITLE })
                    if on_success then
                        on_success(device)
                    end
                end)
            end)
        end)
    end)
end

--- Deploy, then run the launch target on the device.
---@param opts qss.cmake.DeployOpts?
function M.run(opts)
    M.deploy(opts, function(device)
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
---@param opts qss.cmake.DeployOpts?
function M.debug(opts)
    opts = opts or {}
    local selected = devices.selected()
    if not opts.force and blocked(remote_doctor.debug(selected), 'Debug blocked') then
        return
    end

    M.deploy({ force = true }, function(device)
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

--- Where this build runs: here, or on the device it was configured for.
---
--- A cross build cannot start on this machine at all, so the run keys send it
--- to the device instead of handing the host a binary it refuses. Configured
--- for the device means two things: cmake cross compiles, and
--- CMAKE_INSTALL_PREFIX is the directory that device holds. The second one is
--- not bookkeeping. The prefix is what the RPATH and the QML import paths
--- inside the binary were built from, so a build carrying another prefix is a
--- build for another machine.
---@param opts qss.cmake.DeployOpts?
---@param there fun(opts: qss.cmake.DeployOpts?) what runs it on the device
---@param here string the :CMake command that runs it on this machine
local function wherever_it_runs(opts, there, here)
    if not state.cross_compiling() then
        return vim.cmd(here)
    end

    ---@param device qss.remote.Device
    local function once_chosen(device)
        local values = state.cache_values() or {}
        if device.prefix and values.CMAKE_INSTALL_PREFIX == device.prefix then
            return there(opts)
        end

        findings.notify({
            {
                level = 'error',
                text = ('this build installs to %s, and %s holds %s')
                    :format(values.CMAKE_INSTALL_PREFIX or '(unset)', device.name,
                        device.prefix or '(no prefix)'),
                fix = ':CMakeOptions  (<leader>mv), then configure',
            },
        }, 'A cross build with nowhere to run', TITLE)
    end

    -- pick() is only reached with several devices declared: selected() answers
    -- by itself when the project declares one. It also reports the case where
    -- the project declares none.
    local device = devices.selected()
    if device then
        return once_chosen(device)
    end
    devices.pick(once_chosen)
end

--- <leader>mr: run it where it runs.
---@param opts qss.cmake.DeployOpts?
function M.run_wherever(opts)
    wherever_it_runs(opts, M.run, 'CMakeRun')
end

--- <leader>md: debug it where it runs.
---@param opts qss.cmake.DeployOpts?
function M.debug_wherever(opts)
    wherever_it_runs(opts, M.debug, 'CMakeDebug')
end

return M
