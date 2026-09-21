-- What cargo knows about the project: its members, their targets and their
-- features.
--
-- `cargo metadata --no-deps` answers in a quarter of a second on a fifteen-crate
-- workspace, so the answer is kept for the session rather than on disk. It is
-- dropped when a manifest or a lock file is written, which is the only thing
-- that changes it.
--
-- --no-deps matters twice over: it keeps cargo from resolving the registry,
-- which is what makes the call slow, and it limits the packages to the members
-- of the workspace, which is the only thing anything here wants to build.

local project = require('qss_nvim.cargo.project')

local M = {}

---@class qss.cargo.Target
---@field crate string the package that declares it
---@field name string
---@field kind string "bin", "example", "lib", "test" or "bench"
---@field src_path string?

---@type table<string, table|false>
local loaded = {}

---@param root string
---@return table|false
local function read(root)
    if vim.fn.executable('cargo') ~= 1 then
        return false
    end

    local result = vim.system(
        { 'cargo', 'metadata', '--no-deps', '--format-version', '1' },
        { cwd = root, text = true }):wait()
    if result.code ~= 0 then
        return false
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout)
    if not ok or type(decoded) ~= 'table' then
        return false
    end
    return decoded
end

--- Everything cargo reports, or nil when it could not be asked. A manifest that
--- does not parse counts as no answer, because every caller would otherwise
--- have to tell an empty project from a broken one.
---@param root string?
---@return table?
function M.load(root)
    root = root or project.root()
    if not root then
        return nil
    end

    if loaded[root] == nil then
        loaded[root] = read(root)
    end
    return loaded[root] or nil
end

--- Ask cargo again on the next call.
function M.invalidate()
    loaded = {}
end

--- The workspace a crate belongs to, and the key every selection is stored
--- under: a profile chosen while editing one member is the profile the whole
--- workspace builds with.
---@param root string?
---@return string?
function M.workspace_root(root)
    local reported = M.load(root)
    if reported and reported.workspace_root then
        return vim.fs.normalize(reported.workspace_root)
    end
    return root or project.root()
end

--- Where cargo writes what it builds, which a `CARGO_TARGET_DIR` or a
--- `.cargo/config.toml` can move away from the workspace entirely.
---@param root string?
---@return string?
function M.target_directory(root)
    local reported = M.load(root)
    if not reported or not reported.target_directory then
        return nil
    end
    return vim.fs.normalize(reported.target_directory)
end

--- The workspace members, by name.
---@param root string?
---@return string[]
function M.packages(root)
    local reported = M.load(root)
    if not reported then
        return {}
    end

    local names = {}
    for _, package in ipairs(reported.packages or {}) do
        names[#names + 1] = package.name
    end
    table.sort(names)
    return names
end

--- Every target of one kind in the workspace. A crate declares its kind as a
--- list, because one target can be several things at once, a lib that is also
--- a proc-macro being the usual case.
---@param kind string "bin", "example", "lib", "test" or "bench"
---@param root string?
---@return qss.cargo.Target[]
function M.targets(kind, root)
    local reported = M.load(root)
    if not reported then
        return {}
    end

    local targets = {}
    for _, package in ipairs(reported.packages or {}) do
        for _, target in ipairs(package.targets or {}) do
            if vim.tbl_contains(target.kind or {}, kind) then
                targets[#targets + 1] = {
                    crate = package.name,
                    name = target.name,
                    kind = kind,
                    src_path = target.src_path,
                }
            end
        end
    end

    table.sort(targets, function(left, right)
        if left.crate ~= right.crate then
            return left.crate < right.crate
        end
        return left.name < right.name
    end)
    return targets
end

--- The directory of each workspace member. A path in a panic message is
--- relative to the directory cargo ran in, and which one that was depends on
--- the crate, so resolving one means trying them.
---@param root string?
---@return string[]
function M.package_dirs(root)
    local reported = M.load(root)
    if not reported then
        return {}
    end

    local dirs = {}
    for _, package in ipairs(reported.packages or {}) do
        if package.manifest_path then
            dirs[#dirs + 1] = vim.fs.dirname(vim.fs.normalize(package.manifest_path))
        end
    end
    return dirs
end

--- Every feature the workspace declares. `default` is left out: it is not a
--- feature to switch on, it is the set that is already on.
---@param root string?
---@return string[]
function M.feature_names(root)
    local reported = M.load(root)
    if not reported then
        return {}
    end

    local seen, names = {}, {}
    for _, package in ipairs(reported.packages or {}) do
        for feature in pairs(package.features or {}) do
            if feature ~= 'default' and not seen[feature] then
                seen[feature] = true
                names[#names + 1] = feature
            end
        end
    end
    table.sort(names)
    return names
end

vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('QssCargoMetadata', { clear = true }),
    pattern = { 'Cargo.toml', 'Cargo.lock' },
    desc = 'Forget what cargo metadata reported',
    callback = function()
        M.invalidate()
    end,
})

return M
