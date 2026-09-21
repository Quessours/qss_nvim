-- Where the kas project is, and how a path inside the build container maps to a
-- path on this machine.
--
-- kas-container bind-mounts three host directories: the repository holding the
-- kas files on /repo, the work directory on /work and the build directory on
-- /build. Everything the build prints names the container path, bblayers.conf
-- and every compiler error included, and nothing here can open such a path.
-- Plain kas builds on the host, so there the two sides are the same path and
-- the mount list is empty.

local cache = require('qss_nvim.cache').store('qss_kas')

local M = {}

-- What marks a kas project. `.config.yaml` is the file `kas menu` writes, and
-- it is also what kas-container falls back to when a command names no config.
local CONFIG_PATTERNS = {
    'kas*.yml',
    'kas*.yaml',
    'kas/*.yml',
    'kas/*.yaml',
    '.config.yaml',
}

---@type table<string, string|false>
local root_of = {}

---@type table<string, string|false>
local git_root_of = {}

--- The git repository a directory belongs to, which is also what kas-container
--- mounts on /repo.
---@param dir string
---@return string?
local function git_toplevel(dir)
    local cached = git_root_of[dir]
    if cached ~= nil then
        return cached or nil
    end

    local found = vim.fn.systemlist({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' })[1]
    ---@type string|false
    local toplevel = false
    if vim.v.shell_error == 0 and found and found ~= '' then
        toplevel = vim.fs.normalize(found)
    end

    git_root_of[dir] = toplevel
    return toplevel or nil
end

--- Whether a directory itself holds a kas config. The glob asks about this one
--- directory, so the walk below stays one glob per level: a search that climbed
--- the ancestors here would repeat the whole chain at every level.
---@param dir string
---@return boolean
local function has_config(dir)
    for _, pattern in ipairs(CONFIG_PATTERNS) do
        if #vim.fn.glob(dir .. '/' .. pattern, true, true) > 0 then
            return true
        end
    end
    return false
end

--- The project a directory belongs to, searching upwards.
---
--- The outermost match wins, not the nearest. Layers ship example kas files of
--- their own, meta-raspberrypi holds a kas-poky-rpi.yml, and a recipe opened
--- out of such a layer would otherwise answer with the layer. A layer is also
--- its own git checkout, so the git toplevel is no boundary to stop at either:
--- climbing from a recipe crosses one on the way up to the project. The search
--- stops below the home directory instead.
---@param start string a directory
---@return string?
local function climb(start)
    local cached = root_of[start]
    if cached ~= nil then
        return cached or nil
    end

    local home = vim.fs.normalize(vim.env.HOME or '')
    local outermost = nil
    local dir = start

    while dir and dir ~= '/' and dir ~= home do
        if has_config(dir) then
            outermost = dir
        end

        local parent = vim.fs.dirname(dir)
        if parent == dir then
            break
        end
        dir = parent
    end

    root_of[start] = outermost or false
    return outermost
end

--- The directory holding the kas configs.
---
--- With no argument the directory nvim runs in decides, the way the cmake
--- modules here take it, and the buffer is only the fallback for a session
--- started outside any project. A recipe opened from a layer therefore does not
--- move the project, and neither does a task output buffer.
---@param path string? a file or directory to resolve from instead
---@return string?
function M.root(path)
    if path and path ~= '' then
        local start = vim.fs.normalize(path)
        if vim.fn.isdirectory(start) == 0 then
            start = vim.fs.dirname(start)
        end
        return climb(start)
    end

    local cwd = vim.uv.cwd()
    local from_cwd = cwd and climb(vim.fs.normalize(cwd))
    if from_cwd then
        return from_cwd
    end

    local name = vim.api.nvim_buf_get_name(0)
    if name == '' then
        return nil
    end
    return climb(vim.fs.dirname(vim.fs.normalize(name)))
end

--- Every kas config in the project, as paths relative to the root. The order is
--- the order the pickers and the task params offer them in.
---@param root string?
---@return string[]
function M.configs(root)
    root = root or M.root()
    if not root then
        return {}
    end

    local names = {}
    for _, pattern in ipairs(CONFIG_PATTERNS) do
        for _, path in ipairs(vim.fn.glob(root .. '/' .. pattern, true, true)) do
            names[#names + 1] = path:sub(#root + 2)
        end
    end
    table.sort(names)
    return names
end

--- What a config is, which decides whether kas can build an environment from it
--- on its own.
---
--- kas builds the environment out of the repositories it checks out, so a
--- config that declares none and includes none is a fragment: `kas shell` on
--- one fails with "Did not find any init-build-env script". A config that only
--- includes another one is fine, because the include brings the repos with it.
---@param root string
---@param name string relative to the root
---@return "repos"|"includes"|"fragment"
function M.config_kind(root, name)
    local path = root .. '/' .. name
    if vim.fn.filereadable(path) == 0 then
        return 'fragment'
    end

    local includes = false
    for _, line in ipairs(vim.fn.readfile(path)) do
        if line:match('^repos:') then
            return 'repos'
        end
        -- The include list sits under the header, so it is indented.
        if line:match('^%s*includes:') then
            includes = true
        end
    end

    if includes then
        return 'includes'
    end
    return 'fragment'
end

--- Whether kas can resolve a build environment from this config alone.
---@param root string
---@param name string relative to the root
---@return boolean
function M.is_standalone(root, name)
    return M.config_kind(root, name) ~= 'fragment'
end

--- The config a command uses when nobody names one: the resolved config kas
--- menu writes, then the first one that can stand on its own, then whatever
--- comes first.
---@param root string?
---@return string?
function M.default_config(root)
    root = root or M.root()
    if not root then
        return nil
    end

    local names = M.configs(root)
    for _, name in ipairs(names) do
        if name == '.config.yaml' then
            return name
        end
    end
    -- A config that declares the repos itself before one that only includes
    -- another, because the second is usually a variant of the first.
    for _, name in ipairs(names) do
        if M.config_kind(root, name) == 'repos' then
            return name
        end
    end
    for _, name in ipairs(names) do
        if M.config_kind(root, name) == 'includes' then
            return name
        end
    end
    return names[1]
end

--- Whether every file of a config list is still there. kas takes one config or
--- several joined by a colon, and it refuses to start when one of them is
--- missing, so a stale memory is worse than none.
---@param root string
---@param config string
---@return boolean
local function all_readable(root, config)
    if config == '' then
        return false
    end

    for name in vim.gsplit(config, ':', { plain = true }) do
        local path = root .. '/' .. name
        if name:sub(1, 1) == '/' then
            path = name
        end
        if name == '' or vim.fn.filereadable(path) == 0 then
            return false
        end
    end
    return true
end

--- The config every command and picker uses. A project layers several of them,
--- and which one is meant is a choice, so the choice is remembered.
---@param root string?
---@return string?
function M.selected_config(root)
    root = root or M.root()
    if not root then
        return nil
    end

    local remembered = cache.get(cache.key(root, 'config'))
    if remembered and all_readable(root, remembered) then
        return remembered
    end
    return M.default_config(root)
end

--- Remember the config to use. `name` may join several with a colon, which is
--- how kas layers one config over another.
---@param name string
---@param root string?
function M.select_config(name, root)
    root = root or M.root()
    if root then
        cache.set(cache.key(root, 'config'), name)
    end
end

--- `kas-container` when it is installed, and plain `kas` otherwise. The mount
--- list depends on the answer, so everything else asks this and not the PATH.
---@return string?
function M.runner()
    if vim.fn.executable('kas-container') == 1 then
        return 'kas-container'
    end
    if vim.fn.executable('kas') == 1 then
        return 'kas'
    end
    return nil
end

--- What kas-container mounts on /repo: the repository the kas files live in.
---@param root string
---@return string
local function repo_dir(root)
    return git_toplevel(root) or root
end

--- What kas-container mounts on /work. kas takes this from the directory it was
--- started in, which for every task started here is the project root.
---@param root string
---@return string
local function work_dir(root)
    local from_env = vim.env.KAS_WORK_DIR
    if from_env and from_env ~= '' then
        return vim.fs.normalize(from_env)
    end
    return root
end

--- What kas-container mounts on /build, and where bblayers.conf and the whole
--- of tmp/work end up.
---@param root string?
---@return string?
function M.build_dir(root)
    root = root or M.root()
    if not root then
        return nil
    end

    local from_env = vim.env.KAS_BUILD_DIR
    if from_env and from_env ~= '' then
        return vim.fs.normalize(from_env)
    end
    return work_dir(root) .. '/build'
end

---@class qss.kas.Mount
---@field container string
---@field host string

--- The bind mounts of a kas-container build, longest host path first, so that a
--- build directory sitting inside the work directory is matched before it.
---@param root string?
---@return qss.kas.Mount[]
function M.mounts(root)
    root = root or M.root()
    if not root or M.runner() ~= 'kas-container' then
        return {}
    end

    local build = M.build_dir(root)
    if not build then
        return {}
    end

    local mounts = {
        { container = '/build', host = build },
        { container = '/work',  host = work_dir(root) },
        { container = '/repo',  host = repo_dir(root) },
    }
    table.sort(mounts, function(a, b)
        return #a.host > #b.host
    end)
    return mounts
end

---@param path string
---@param prefix string
---@return boolean
local function starts_with(path, prefix)
    if path == prefix then
        return true
    end
    return path:sub(1, #prefix + 1) == prefix .. '/'
end

--- A path as this machine sees it. Paths that are already host paths, and paths
--- under no mount, come back unchanged.
---@param path string
---@param root string?
---@return string
function M.to_host(path, root)
    for _, mount in ipairs(M.mounts(root)) do
        if starts_with(path, mount.container) then
            return mount.host .. path:sub(#mount.container + 1)
        end
    end
    return path
end

--- A path as the container sees it, for an argument handed to bitbake.
---@param path string
---@param root string?
---@return string
function M.to_container(path, root)
    local absolute = vim.fs.normalize(vim.fn.fnamemodify(path, ':p')):gsub('/$', '')
    for _, mount in ipairs(M.mounts(root)) do
        if starts_with(absolute, mount.host) then
            return mount.container .. absolute:sub(#mount.host + 1)
        end
    end
    return path
end

--- The argv of a kas command. `config` may name several files joined by a
--- colon, which is how kas layers one config over another.
---@param subcommand string
---@param opts { config: string?, args: string[]?, bitbake_args: string[]? }?
---@return string[]?
function M.command(subcommand, opts)
    local runner = M.runner()
    if not runner then
        return nil
    end
    opts = opts or {}

    local argv = { runner, subcommand }
    vim.list_extend(argv, opts.args or {})

    local config = opts.config
    if config == nil then
        config = M.selected_config()
    end
    if config and config ~= '' then
        argv[#argv + 1] = config
    end

    if opts.bitbake_args and #opts.bitbake_args > 0 then
        argv[#argv + 1] = '--'
        vim.list_extend(argv, opts.bitbake_args)
    end
    return argv
end

--- One command run inside the build environment, which is the only place
--- bitbake exists. kas-container refuses -E, so nothing here passes it.
---
--- `keep_config` is for a query: with -k kas skips the steps that rewrite
--- local.conf and bblayers.conf, so asking what tasks a recipe has cannot
--- change the build directory underneath you.
---@param command string
---@param opts { config: string?, keep_config: boolean? }?
---@return string[]?
function M.shell_command(command, opts)
    opts = opts or {}

    local args = {}
    if opts.keep_config then
        args[#args + 1] = '-k'
    end
    vim.list_extend(args, { '-c', command })

    return M.command('shell', { config = opts.config, args = args })
end

return M
