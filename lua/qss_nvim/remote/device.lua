-- The machine a build is deployed to, and the argv lists that reach it.
--
-- A device is an address. `host` holds it, and `user`, `ssh_port` and `key`
-- sit beside it for the cases the defaults miss. A board on the desk answers
-- long before anyone writes it down, and the address of the target a project
-- deploys to belongs with that project rather than in ~/.ssh/config.
--
-- An `ssh` Host alias is read when no host is given, and then ~/.ssh/config
-- answers for the address, the user, the port, the key and the jump host.
--
-- What no transport can know stays here either way: where the files go on that
-- machine, how to start the program, and which cross debugger reads its
-- binaries.
--
-- A project declares its devices in its .nvim.lua, which init.lua reads through
-- exrc, so nothing about one machine is ever committed:
--
--     vim.g.qss_devices = {
--         {
--             name = 'rpi4',
--             host = '192.168.1.42',
--             prefix = '/home/root/app',
--             env = { QT_QPA_PLATFORM = 'eglfs' },
--             before_deploy = { 'systemctl stop myapp' },
--             before_run = { 'pkill -f myapp' },
--             gdb = sdk .. '/sysroots/.../aarch64-poky-linux-gdb',
--             sysroot = sdk .. '/sysroots/cortexa72-poky-linux',
--             source_map = { ['/work'] = root, ['/build'] = build },
--         },
--     }

local cache = require('qss_nvim.cache').store('qss_remote')

local M = {}

---@class qss.remote.Device
---@field name string what the picker shows
---@field host string? the address, an IP or a hostname
---@field user string who logs in, when the device is an address
---@field ssh string? the Host alias from ~/.ssh/config, read when host is absent
---@field target string what ssh and rsync are handed: user@host, or the alias
---@field ssh_port integer the port sshd listens on
---@field key string? an identity file for the login
---@field ssh_options string[] further ssh options, passed through as they are
---@field rsync_options string[] further rsync options, passed through as they are
---@field prefix string? CMAKE_INSTALL_PREFIX, and the directory on the device
---@field env table<string, string> environment for the program
---@field args string[] arguments for the program
---@field run_command string? a program on the device to run instead of the launch target
---@field before_deploy string[] shell commands to run on the device before the copy
---@field before_run string[] shell commands to run on the device before the program
---@field gdb string? the cross gdb of the SDK, for a debug session
---@field gdbserver string what starts the server on the device
---@field sysroot string? where the cross gdb looks up shared libraries
---@field source_map table<string, string> build-time path to path on this machine
---@field port integer the port gdbserver listens on, not the login port

local DEFAULT_PORT = 2345
local DEFAULT_GDBSERVER = 'gdbserver'
local DEFAULT_SSH_PORT = 22

--- The account a Yocto image offers. The login name of whoever sits here is
--- almost never a user the device has heard of.
local DEFAULT_USER = 'root'

--- accept-new stores the key of a device seen for the first time instead of
--- asking about it. Nothing can answer that question: these calls run in a
--- task, so the alternative to storing the key is a hang. A key that changed
--- still stops the connection, which is the case worth stopping for.
local DEFAULT_SSH_OPTIONS = {
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'ConnectTimeout=10',
}

--- Directories a whole system lives in. rsync --delete against one of them
--- removes everything the deploy did not bring, which on a device means the
--- operating system.
local SHARED_PREFIXES = {
    ['/'] = true,
    ['/bin'] = true,
    ['/etc'] = true,
    ['/home'] = true,
    ['/lib'] = true,
    ['/opt'] = true,
    ['/root'] = true,
    ['/usr'] = true,
    ['/var'] = true,
}

--- A single command is the common case, so one string is accepted where a list
--- is meant.
---@param value string|string[]|nil
---@return string[]
local function as_list(value)
    if type(value) == 'string' then
        return { value }
    end
    if type(value) == 'table' then
        return vim.tbl_filter(function(entry)
            return type(entry) == 'string' and vim.trim(entry) ~= ''
        end, value)
    end
    return {}
end

---@param path string?
---@return string?
local function without_trailing_slash(path)
    if not path or path == '/' then
        return path
    end
    return (path:gsub('/+$', ''))
end

---@param entry table
---@param fallback_name string
---@return qss.remote.Device
local function normalize(entry, fallback_name)
    local user = entry.user or DEFAULT_USER

    -- An alias is handed over untouched. The login user of an alias is what
    -- ~/.ssh/config says, and a user pasted in front of it here would override
    -- that file rather than complete it.
    local target = entry.ssh
    if entry.host then
        target = ('%s@%s'):format(user, entry.host)
    end

    local key = nil
    if entry.key then
        key = vim.fn.expand(entry.key)
    end

    return {
        name = entry.name or fallback_name,
        host = entry.host,
        user = user,
        ssh = entry.ssh,
        target = target,
        ssh_port = tonumber(entry.ssh_port) or DEFAULT_SSH_PORT,
        key = key,
        ssh_options = entry.ssh_options or {},
        rsync_options = entry.rsync_options or {},
        prefix = without_trailing_slash(entry.prefix),
        env = entry.env or {},
        args = entry.args or {},
        run_command = entry.run_command,
        before_deploy = as_list(entry.before_deploy),
        before_run = as_list(entry.before_run),
        gdb = entry.gdb,
        gdbserver = entry.gdbserver or DEFAULT_GDBSERVER,
        sysroot = without_trailing_slash(entry.sysroot),
        source_map = entry.source_map or {},
        port = tonumber(entry.port) or DEFAULT_PORT,
    }
end

--- Every device the project declares, in a stable order.
---
--- Both shapes of the table are read: a list, and a map from name to device.
--- vim.g hands back a copy either way, and a map is the shape someone reaches
--- for when the name is the interesting part.
---@return qss.remote.Device[]
function M.list()
    local declared = vim.g.qss_devices
    if type(declared) ~= 'table' then
        return {}
    end

    local devices = {}
    for key, entry in pairs(declared) do
        local addressed = type(entry) == 'table' and
            (type(entry.host) == 'string' or type(entry.ssh) == 'string')
        if addressed then
            local fallback_name = entry.host or entry.ssh
            if type(key) == 'string' then
                fallback_name = key
            end
            devices[#devices + 1] = normalize(entry, fallback_name)
        end
    end

    table.sort(devices, function(left, right)
        return left.name < right.name
    end)
    return devices
end

---@param name string
---@return qss.remote.Device?
function M.by_name(name)
    for _, device in ipairs(M.list()) do
        if device.name == name then
            return device
        end
    end
    return nil
end

---@return string
local function root()
    return vim.fs.normalize(vim.uv.cwd() or '.')
end

---@return string
local function cache_key()
    return cache.key(root(), 'device')
end

--- The device to act on: the only one when the project declares one, and
--- otherwise the remembered choice. A remembered name that no longer matches a
--- declared device is dropped rather than passed on, the way a stale kas config
--- is.
---@return qss.remote.Device?
function M.selected()
    local devices = M.list()
    if #devices == 0 then
        return nil
    end
    if #devices == 1 then
        return devices[1]
    end

    local remembered = cache.get(cache_key())
    if type(remembered) ~= 'string' then
        return nil
    end
    return M.by_name(remembered)
end

---@param name string
---@return qss.remote.Device?
function M.select(name)
    local device = M.by_name(name)
    if not device then
        return nil
    end
    cache.set(cache_key(), device.name)
    return device
end

--- Ask the picker for a device, and remember the answer.
---@param on_choice fun(device: qss.remote.Device)
function M.pick(on_choice)
    local devices = M.list()
    if #devices == 0 then
        return vim.notify('no device is declared; see :help qss-devices',
            vim.log.levels.ERROR, { title = 'Deploy' })
    end

    vim.ui.select(devices, {
        prompt = 'Device',
        format_item = function(device)
            local where = device.prefix or '(no prefix)'
            return ('%s  %s:%s'):format(device.name, device.target, where)
        end,
    }, function(device)
        if not device then
            return
        end
        M.select(device.name)
        on_choice(device)
    end)
end

---@type table<string, table>
local resolved = {}

--- Where the device actually is. The debugger needs this: it opens the port
--- itself, and it takes a host and not an alias.
---
--- An address is already the answer. An alias goes through ssh's own parser, so
--- an Include, a Match block or a pattern all give the same answer here as they
--- do to ssh.
---@param device qss.remote.Device
---@return { hostname: string, port: string, user: string }?
function M.resolve(device)
    if device.host then
        return {
            hostname = device.host,
            port = tostring(device.ssh_port),
            user = device.user,
        }
    end

    local known = resolved[device.target]
    if known then
        return known
    end

    local lines = vim.fn.systemlist({ 'ssh', '-G', device.target })
    if vim.v.shell_error ~= 0 then
        return nil
    end

    local settings = {}
    for _, line in ipairs(lines) do
        local name, value = line:match('^(%S+)%s+(.*)$')
        if name then
            settings[name:lower()] = value
        end
    end
    if not settings.hostname then
        return nil
    end

    local answer = {
        hostname = settings.hostname,
        port = settings.port or '22',
        user = settings.user or '',
    }
    resolved[device.target] = answer
    return answer
end

--- Every word quoted for the shell on the device. The local shell never sees
--- this string: ssh hands its argument to the remote shell as it is.
---@param words string[]
---@return string
function M.quote(words)
    return table.concat(vim.tbl_map(vim.fn.shellescape, words), ' ')
end

--- The hooks the device declares, as one command for its shell.
---
--- These are shell commands and not argv lists, because that is how they are
--- written: `systemctl stop myapp`, `pkill -f myapp`. They are passed through
--- unquoted, so a pipe or an || in one of them means what it says.
---
--- Their failure never stops what comes after. A `pkill` with nothing to kill
--- exits 1, and a stop of a unit that is already stopped is exactly the state
--- the hook is there to reach. A failure that matters is reported by the step
--- that follows: rsync says "Text file busy" when the old binary is still
--- running, and that is the message worth reading.
---@param commands string[]
---@return string?
function M.hook_command(commands)
    if #commands == 0 then
        return nil
    end
    return ('( %s ; true )'):format(table.concat(commands, ' ; '))
end

---@class qss.remote.CommandOpts
---@field cwd string? where to run, defaults to the prefix
---@field env boolean? false leaves the device environment alone
---@field before string[]? shell commands to run first, on the device

--- A command for the remote shell: into the working directory, the hooks, then
--- the program with its environment.
---@param device qss.remote.Device
---@param words string[] the program and its arguments
---@param opts qss.remote.CommandOpts?
---@return string
function M.remote_command(device, words, opts)
    opts = opts or {}

    -- Every part is joined with && , so a failed cd stops there instead of
    -- running the program in the home directory of the login user.
    local parts = {}
    local cwd = opts.cwd or device.prefix
    if cwd then
        parts[#parts + 1] = 'cd ' .. vim.fn.shellescape(cwd)
    end

    local hooks = M.hook_command(opts.before or {})
    if hooks then
        parts[#parts + 1] = hooks
    end

    -- The environment belongs to the program, so the two are one part of the
    -- chain and not two.
    local program = M.quote(words)

    local names = vim.tbl_keys(device.env)
    if opts.env ~= false and #names > 0 then
        table.sort(names)
        local assignments = {}
        for _, name in ipairs(names) do
            assignments[#assignments + 1] = ('%s=%s'):format(name, device.env[name])
        end
        -- env takes A=b as one word, so quoting the pair whole is what keeps a
        -- value holding a space intact.
        program = ('env %s %s'):format(M.quote(assignments), program)
    end

    parts[#parts + 1] = program
    return table.concat(parts, ' && ')
end

---@class qss.remote.SshOpts
---@field tty boolean? allocate a terminal, so the program sees one and Ctrl-C reaches it

--- The options that every call to this device carries, for ssh and for the
--- transport rsync starts. A device that declares neither a port nor a key gets
--- the defaults alone, which is what leaves ~/.ssh/config in charge of an alias.
---@param device qss.remote.Device
---@return string[]
function M.ssh_flags(device)
    local flags = vim.list_extend({}, DEFAULT_SSH_OPTIONS)
    if device.ssh_port ~= DEFAULT_SSH_PORT then
        vim.list_extend(flags, { '-p', tostring(device.ssh_port) })
    end
    if device.key then
        vim.list_extend(flags, { '-i', device.key })
    end
    return vim.list_extend(flags, device.ssh_options)
end

---@param device qss.remote.Device
---@param command string? nil opens a shell
---@param opts qss.remote.SshOpts?
---@return string[]
function M.ssh_argv(device, command, opts)
    local argv = { 'ssh' }
    if (opts or {}).tty then
        argv[#argv + 1] = '-t'
    end
    vim.list_extend(argv, M.ssh_flags(device))
    argv[#argv + 1] = device.target
    if command then
        argv[#argv + 1] = command
    end
    return argv
end

--- Whether the destination is the deploy's own directory, and therefore whether
--- rsync is allowed to remove what the deploy did not bring.
---@param device qss.remote.Device
---@return boolean
function M.can_delete(device)
    local prefix = device.prefix
    if not prefix or SHARED_PREFIXES[prefix] then
        return false
    end

    local depth = 0
    for _ in prefix:gmatch('[^/]+') do
        depth = depth + 1
    end
    return depth >= 2
end

--- The copy step. The trailing slash on the source is what makes rsync copy the
--- contents of the staging tree rather than the tree itself.
---
--- The same ssh options reach rsync through -e, which rsync splits on
--- whitespace and reads no quotes in. A key whose path holds a space therefore
--- cannot be passed this way.
---
--- `rsync_options` comes last of the options, which is what lets it override
--- the defaults above: rsync keeps the last of two flags that contradict, and
--- --no-perms and its family undo the parts of -a. Last also means a --delete
--- declared there survives the shared-prefix guard, so the device that asks
--- for it gets it.
---@param device qss.remote.Device
---@param staging string the directory holding the staged tree
---@return string[]
function M.rsync_argv(device, staging)
    local source = (staging:gsub('/+$', '')) .. '/'
    local argv = { 'rsync', '-az', '--info=progress2' }
    if M.can_delete(device) then
        argv[#argv + 1] = '--delete'
    end

    local transport = vim.list_extend({ 'ssh' }, M.ssh_flags(device))
    vim.list_extend(argv, { '-e', table.concat(transport, ' ') })
    vim.list_extend(argv, device.rsync_options)

    vim.list_extend(argv, { source, ('%s:%s/'):format(device.target, device.prefix) })
    return argv
end

return M
