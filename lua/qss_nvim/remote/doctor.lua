-- What a deploy needs that is not there yet.
--
-- These checks are deliberately not part of :CMakeDoctor. That one gates every
-- build through :CMakeBuildChecked, and a project with no device declared has
-- nothing wrong with it: it builds for this machine and always did.

local device_module = require('qss_nvim.remote.device')
local state = require('qss_nvim.cmake-tools.state')

local M = {}

---@param name string
---@return boolean
local function installed(name)
    return vim.fn.executable(name) == 1
end

--- The adapter cppdbg is registered with in nvim-dap/adapters/cppdbg.lua, which
--- mason installs as a script and not as a binary on PATH.
local DEBUG_ADAPTER = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7'

--- Whether a login gets all the way through without asking for anything.
---
--- BatchMode turns every prompt into a failure, which is the answer this check
--- wants: a deploy runs in a task, nothing there can type a password, so a
--- device that asks for one hangs instead of failing. Both options come before
--- the ones the device carries, because ssh keeps the first value it is given
--- for a setting and the device default is a longer timeout.
---@param device qss.remote.Device
---@return boolean
local function answers(device)
    local argv = { 'ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5' }
    vim.list_extend(argv, device_module.ssh_flags(device))
    vim.list_extend(argv, { device.target, 'true' })

    vim.fn.system(argv)
    return vim.v.shell_error == 0
end

--- Whether the deploy can run at all, without the debugger checks, so that
--- :CMakeDeploy does not ask for a cross gdb it never calls.
---@param device qss.remote.Device?
---@return qss.Finding[]
function M.run(device)
    local findings = {}
    ---@param level "ok"|"warn"|"error"
    local function add(level, text, fix)
        table.insert(findings, { level = level, text = text, fix = fix })
    end

    for _, tool in ipairs({ 'ssh', 'rsync' }) do
        if not installed(tool) then
            add('error', tool .. ' is not installed', 'install ' .. tool)
        end
    end

    local declared = device_module.list()
    if #declared == 0 then
        add('error', 'no device is declared',
            'declare vim.g.qss_devices in .nvim.lua; see :help qss-devices')
        return findings
    end

    if not device then
        add('error', ('%d devices are declared and none is selected'):format(#declared),
            ':CMakeSelectDevice  (<leader>mh)')
        return findings
    end

    if not device.prefix then
        add('error', ('device %s declares no prefix'):format(device.name),
            "prefix = '/home/root/app' in the device table")
        return findings
    end

    local address = device_module.resolve(device)
    if not address then
        add('error', ('ssh cannot resolve the alias %s'):format(device.ssh),
            ('add a Host %s block to ~/.ssh/config, or give the device a host'):format(device.ssh))
    elseif answers(device) then
        add('ok', ('%s answers on port %s'):format(device.target, address.port))
    else
        -- Reachable and refusing are both live answers, and the one this
        -- cannot tell apart is the one that matters: a prompt no task can
        -- answer. Hence a warning, and a command to run by hand.
        add('warn', ('%s did not answer without a prompt'):format(device.target),
            ('run  ssh %s true  by hand and see what it asks for'):format(device.target))
    end

    local values = state.cache_values()
    if not values then
        add('warn', 'the project is not configured yet',
            ':CMakeGenerate  (<leader>mg)')
    elseif values.CMAKE_INSTALL_PREFIX ~= device.prefix then
        add('warn', ('CMAKE_INSTALL_PREFIX is %s, and the device holds %s')
            :format(values.CMAKE_INSTALL_PREFIX or '(unset)', device.prefix),
            ':CMakeOptions  (<leader>mv)')
    else
        add('ok', 'the install prefix matches the device')
    end

    if not device_module.can_delete(device) then
        add('warn', ('%s is a shared directory, so stale files stay behind')
            :format(device.prefix))
    end

    return findings
end

--- The debug session needs the cross toolchain as well: the gdb that reads the
--- target binaries, the sysroot its shared libraries come from, and the adapter
--- that drives it.
---@param device qss.remote.Device?
---@return qss.Finding[]
function M.debug(device)
    local findings = M.run(device)
    if not device then
        return findings
    end

    ---@param level "ok"|"warn"|"error"
    local function add(level, text, fix)
        table.insert(findings, { level = level, text = text, fix = fix })
    end

    if vim.fn.filereadable(DEBUG_ADAPTER) ~= 1 then
        add('error', 'OpenDebugAD7 is not installed',
            ':MasonInstall cpptools')
    end

    if not device.gdb then
        add('error', ('device %s declares no gdb'):format(device.name),
            'gdb = <sdk>/sysroots/x86_64-pokysdk-linux/usr/bin/<target>/<target>-gdb')
    elseif not installed(device.gdb) then
        add('error', ('the cross gdb %s is not executable'):format(device.gdb),
            'check the SDK path in .nvim.lua')
    end

    if device.sysroot and vim.fn.isdirectory(device.sysroot) ~= 1 then
        add('error', ('the sysroot %s is not a directory'):format(device.sysroot),
            'check the SDK path in .nvim.lua')
    elseif not device.sysroot then
        add('warn', 'no sysroot is declared, so gdb reads the host shared libraries',
            'sysroot = <sdk>/sysroots/<machine>')
    end

    return findings
end

return M
