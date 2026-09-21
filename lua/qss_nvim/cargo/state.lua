-- What the project is currently set to build, and what that means on the
-- command line and on disk.
--
-- cargo has no equivalent of a CMake cache: every invocation states the whole
-- selection again, so a profile or a feature set is a choice this config has to
-- hold rather than read back. The choices are kept per workspace and survive a
-- restart, because a crate cross-compiled to wasm32 yesterday is still being
-- cross-compiled today.
--
-- Everything is validated on the way out. A remembered target that the manifest
-- no longer declares, or a triple rustup no longer has, would make cargo refuse
-- the whole command, so a stale answer is dropped in favour of the default.

local cache = require('qss_nvim.cache').store('qss_cargo')
local metadata = require('qss_nvim.cargo.metadata')

local M = {}

---@class qss.cargo.Features
---@field mode "default"|"all"|"none"|"list"
---@field list string[] the features to switch on, for the "list" mode alone

local FEATURE_MODES = { default = true, all = true, none = true, list = true }

--- The cache key of one selection, or nil outside a cargo project.
---@param name string
---@param root string?
---@return string?
local function key_of(name, root)
    local workspace = metadata.workspace_root(root)
    if not workspace then
        return nil
    end
    return cache.key(workspace, name)
end

---@param name string
---@param root string?
---@return any
local function remembered(name, root)
    local key = key_of(name, root)
    if not key then
        return nil
    end
    return cache.get(key)
end

---@param name string
---@param value any
---@param root string?
local function remember(name, value, root)
    local key = key_of(name, root)
    if key then
        cache.set(key, value)
    end
end

--- The profiles a build can use. cargo metadata does not report profiles, so
--- the workspace manifest is the only place the custom ones are named.
---@param root string?
---@return string[]
function M.profiles(root)
    local names = { 'dev', 'release' }

    local workspace = metadata.workspace_root(root)
    if not workspace then
        return names
    end
    local manifest = workspace .. '/Cargo.toml'
    if vim.fn.filereadable(manifest) ~= 1 then
        return names
    end

    local seen = { dev = true, release = true }
    for _, line in ipairs(vim.fn.readfile(manifest)) do
        -- [profile.release.package.foo] tunes one dependency of a profile that
        -- already exists, so the closing bracket has to follow the name.
        local name = line:match('^%s*%[profile%.([%w_%-]+)%]')
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

---@param root string?
---@return string
function M.profile(root)
    local stored = remembered('profile', root)
    if type(stored) == 'string' and vim.tbl_contains(M.profiles(root), stored) then
        return stored
    end
    return 'dev'
end

---@param name string
---@param root string?
function M.select_profile(name, root)
    remember('profile', name, root)
end

--- Where cargo puts what a profile builds. `dev` is the one whose directory is
--- not its own name, and a custom profile uses its name as it stands.
---@param profile string
---@return string
local function profile_dir(profile)
    if profile == 'dev' then
        return 'debug'
    end
    return profile
end

---@param root string?
---@return qss.cargo.Features
function M.features(root)
    local stored = remembered('features', root)
    if type(stored) ~= 'table' or not FEATURE_MODES[stored.mode] then
        return { mode = 'default', list = {} }
    end
    if stored.mode ~= 'list' then
        return { mode = stored.mode, list = {} }
    end

    local declared = metadata.feature_names(root)
    local list = {}
    for _, name in ipairs(stored.list or {}) do
        if vim.tbl_contains(declared, name) then
            list[#list + 1] = name
        end
    end

    -- An explicit list that nothing survived is no longer a choice.
    if #list == 0 then
        return { mode = 'default', list = {} }
    end
    return { mode = 'list', list = list }
end

---@param features qss.cargo.Features
---@param root string?
function M.select_features(features, root)
    remember('features', features, root)
end

--- Whether the workspace still declares a target, so that a crate renamed or
--- removed since the choice was made does not reach the command line.
---@param target qss.cargo.Target?
---@param root string?
---@return boolean
local function target_exists(target, root)
    if type(target) ~= 'table' or not target.name or not target.kind then
        return false
    end
    for _, known in ipairs(metadata.targets(target.kind, root)) do
        if known.name == target.name and known.crate == target.crate then
            return true
        end
    end
    return false
end

--- The bin or example that a run and a debug session launch, and whose crate
--- a build is limited to.
---@param root string?
---@return qss.cargo.Target?
function M.target(root)
    local stored = remembered('target', root)
    if target_exists(stored, root) then
        return stored
    end

    -- One binary in the whole workspace is not a choice worth asking about.
    local binaries = metadata.targets('bin', root)
    if #binaries == 1 then
        return binaries[1]
    end
    return nil
end

---@param target qss.cargo.Target
---@param root string?
function M.select_target(target, root)
    remember('target', target, root)
end

---@type string[]?
local installed_triples

--- The targets rustup has installed. The host is among them, but building for
--- the host is what selecting nothing already means, so this list is only ever
--- about the others.
---@return string[]
function M.triples()
    if installed_triples then
        return installed_triples
    end

    installed_triples = {}
    if vim.fn.executable('rustup') ~= 1 then
        return installed_triples
    end

    local lines = vim.fn.systemlist({ 'rustup', 'target', 'list', '--installed' })
    if vim.v.shell_error ~= 0 then
        return installed_triples
    end

    for _, line in ipairs(lines) do
        local triple = vim.trim(line)
        if triple ~= '' then
            installed_triples[#installed_triples + 1] = triple
        end
    end
    return installed_triples
end

--- The target triple to cross-compile to, or nil to build for this machine.
---@param root string?
---@return string?
function M.triple(root)
    local stored = remembered('triple', root)
    if type(stored) == 'string' and vim.tbl_contains(M.triples(), stored) then
        return stored
    end
    return nil
end

--- Pass nil to go back to building for this machine.
---@param triple string?
---@param root string?
function M.select_triple(triple, root)
    remember('triple', triple, root)
end

--- Where cargo puts the binaries of the current selection. A triple adds a
--- level of its own, which is why this is not the target directory itself.
---@param root string?
---@return string?
function M.artifact_dir(root)
    local target_directory = metadata.target_directory(root)
    if not target_directory then
        return nil
    end

    local parts = { target_directory }
    local triple = M.triple(root)
    if triple then
        parts[#parts + 1] = triple
    end
    parts[#parts + 1] = profile_dir(M.profile(root))
    return table.concat(parts, '/')
end

--- The file the selected target builds to, which is what a debug session
--- launches.
---@param root string?
---@return string?
function M.artifact(root)
    local target = M.target(root)
    local dir = M.artifact_dir(root)
    if not target or not dir then
        return nil
    end

    if target.kind == 'example' then
        return ('%s/examples/%s'):format(dir, target.name)
    end
    return ('%s/%s'):format(dir, target.name)
end

--- The selection as command-line arguments.
---
--- `profile_flag` is the one thing the two tools spell differently: nextest
--- keeps `--profile` for its own profiles and takes the cargo one as
--- `--cargo-profile`. Everything else is shared.
---
--- The target itself is never among them: `--bin` belongs to build and run,
--- while `cargo test` reads it as the name of a test binary, so naming it here
--- would mean something different in each caller.
---@param profile_flag string
---@param root string?
---@return string[]
local function selection_args(profile_flag, root)
    local args = { profile_flag, M.profile(root) }

    local features = M.features(root)
    if features.mode == 'all' then
        args[#args + 1] = '--all-features'
    elseif features.mode == 'none' then
        args[#args + 1] = '--no-default-features'
    elseif features.mode == 'list' then
        vim.list_extend(args, { '--features', table.concat(features.list, ',') })
    end

    local triple = M.triple(root)
    if triple then
        vim.list_extend(args, { '--target', triple })
    end

    local target = M.target(root)
    if target then
        vim.list_extend(args, { '-p', target.crate })
    end
    return args
end

--- The arguments every cargo command of this project carries.
---@param root string?
---@return string[]
function M.cargo_args(root)
    return selection_args('--profile', root)
end

--- The same, for `cargo nextest`.
---@param root string?
---@return string[]
function M.nextest_args(root)
    return selection_args('--cargo-profile', root)
end

--- The whole argument list of a build of the current selection. `cargo build`
--- names the target with --bin or --example, which is the spelling cargo_args
--- leaves out because `cargo test` gives those flags another meaning.
---@param root string?
---@return string[]
function M.build_args(root)
    local args = { 'build' }
    vim.list_extend(args, M.cargo_args(root))

    local target = M.target(root)
    if target and (target.kind == 'bin' or target.kind == 'example') then
        vim.list_extend(args, { '--' .. target.kind, target.name })
    end
    return args
end

return M
