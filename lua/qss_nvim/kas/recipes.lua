-- The recipes of the project, read off the layers rather than out of bitbake.
--
-- `bitbake-layers show-recipes` is the authoritative answer and needs a full
-- parse to give it, so it is a minute of waiting for a list that a single find
-- produces in well under a second. The file names carry everything the pickers
-- and the completion show: the recipe name, its version and the layer it sits
-- in.

local cache = require('qss_nvim.cache').store('qss_kas')
local layers = require('qss_nvim.kas.layers')
local project = require('qss_nvim.kas.project')

local M = {}

local TTL = 24 * 60 * 60

-- The name list that completion asks for on every keystroke, per project root.
---@type table<string, string[]>
local names_of = {}

---@class qss.kas.Recipe
---@field name string
---@field version string? absent for a recipe whose file names no version
---@field layer string the layer directory the file was found in
---@field file string the .bb file
---@field appends string[] .bbappend files for the same name
---@field includes string[] .inc files sitting beside it

--- A recipe file name is `<name>_<version>.bb`, and a name may hold any number
--- of dashes, so the version is what follows the last underscore. An append may
--- write the version as a glob, `foo_1.%.bbappend`, which stays as it is.
---@param path string
---@return string name, string? version
local function split_name(path)
    local stem = vim.fn.fnamemodify(path, ':t:r')
    local name, version = stem:match('^(.*)_([^_]*)$')
    if not name or name == '' then
        return stem, nil
    end
    return name, version
end

---@param roots string[]
---@return string[]
local function recipe_files(roots)
    if #roots == 0 then
        return {}
    end

    local argv = { 'find' }
    vim.list_extend(argv, roots)
    vim.list_extend(argv, {
        '(', '-name', '.git', '-o', '-name', 'tmp', ')', '-prune', '-o',
        '(', '-name', '*.bb', '-o', '-name', '*.bbappend', '-o', '-name', '*.inc', ')',
        '-print',
    })

    local found = vim.fn.systemlist(argv)
    if vim.v.shell_error ~= 0 then
        return {}
    end
    return found
end

--- Which layer of `roots` a file belongs to. The longest match wins, because a
--- layer repository can hold another layer below it.
---@param path string
---@param roots string[]
---@return string
local function layer_of(path, roots)
    local best = ''
    for _, layer in ipairs(roots) do
        if #layer > #best and path:sub(1, #layer + 1) == layer .. '/' then
            best = layer
        end
    end
    return best
end

---@param root string
---@return qss.kas.Recipe[]
local function build_index(root)
    local roots = layers.roots(root)
    local recipes = {}
    local by_name = {}
    local extras = {}

    for _, path in ipairs(recipe_files(roots)) do
        local name, version = split_name(path)
        local extension = vim.fn.fnamemodify(path, ':e')

        if extension == 'bb' then
            local recipe = {
                name = name,
                version = version,
                layer = layer_of(path, roots),
                file = path,
                appends = {},
                includes = {},
            }
            recipes[#recipes + 1] = recipe
            by_name[name] = by_name[name] or {}
            table.insert(by_name[name], recipe)
        else
            extras[#extras + 1] = { name = name, path = path, extension = extension }
        end
    end

    -- An append or an include is attached after the fact, because it can be
    -- read before the recipe it belongs to.
    for _, extra in ipairs(extras) do
        for _, recipe in ipairs(by_name[extra.name] or {}) do
            local field = recipe.includes
            if extra.extension == 'bbappend' then
                field = recipe.appends
            end
            field[#field + 1] = extra.path
        end
    end

    table.sort(recipes, function(a, b)
        if a.name == b.name then
            return (a.version or '') < (b.version or '')
        end
        return a.name < b.name
    end)
    return recipes
end

--- Every recipe of the project.
---
--- The index is rebuilt when the layers have moved since it was written, which
--- is what a `kas build` or a `kas checkout` in another terminal does: a recipe
--- that was upgraded leaves a cached path that opens an empty buffer. The
--- fingerprint costs a few stat calls, and the rebuild about 150ms over a dozen
--- layers.
---@param root string?
---@param opts { refresh: boolean? }?
---@return qss.kas.Recipe[]
function M.list(root, opts)
    root = root or project.root()
    if not root then
        return {}
    end

    local key = cache.key(root, 'recipes')
    local fingerprint = layers.fingerprint(root)

    if (opts or {}).refresh then
        cache.invalidate(key)
        cache.invalidate(cache.key(root, 'layer_scan'))
        names_of[root] = nil
        fingerprint = layers.fingerprint(root)
    else
        local remembered = cache.get(key)
        if remembered and remembered.fingerprint == fingerprint then
            return remembered.recipes
        end
        names_of[root] = nil
    end

    local recipes = build_index(root)
    if #recipes > 0 then
        cache.set(key, { fingerprint = fingerprint, recipes = recipes }, TTL)
    end
    return recipes
end

--- The recipe names, each one once. Completion asks for this on every keystroke,
--- so the answer is kept for the session and dropped when the index is rebuilt.
---@param root string?
---@return string[]
function M.names(root)
    root = root or project.root()
    if not root then
        return {}
    end

    local remembered = names_of[root]
    if remembered then
        return remembered
    end

    local seen = {}
    local names = {}
    for _, recipe in ipairs(M.list(root)) do
        if not seen[recipe.name] then
            seen[recipe.name] = true
            names[#names + 1] = recipe.name
        end
    end

    names_of[root] = names
    return names
end

--- The recipes of one name, newest file order aside, in layer order.
---@param name string
---@param root string?
---@return qss.kas.Recipe[]
function M.by_name(name, root)
    return vim.tbl_filter(function(recipe)
        return recipe.name == name
    end, M.list(root))
end

--- The file to open for a recipe, which is not always the one the index holds.
---
--- A recipe that was upgraded since the index was written carries a new version
--- in its file name, so the path is gone while the recipe is not: opening it
--- would give an empty buffer. The lookup falls back to the name, after a
--- rebuild.
---@param recipe qss.kas.Recipe
---@param root string?
---@return string? path, boolean rebuilt
function M.resolve(recipe, root)
    if vim.fn.filereadable(recipe.file) == 1 then
        return recipe.file, false
    end

    M.list(root, { refresh = true })
    local current = M.by_name(recipe.name, root)[1]
    if current and vim.fn.filereadable(current.file) == 1 then
        return current.file, true
    end
    return nil, true
end

--- Image recipes, which are the recipes worth offering as a build target. The
--- test is the name, because the alternative is opening every recipe in the
--- tree to see what it inherits.
---@param root string?
---@return string[]
function M.image_names(root)
    local names = {}
    local seen = {}
    for _, recipe in ipairs(M.list(root)) do
        local is_image = recipe.name:find('%-image') or recipe.name:find('^image%-')
        if is_image and not seen[recipe.name] then
            seen[recipe.name] = true
            names[#names + 1] = recipe.name
        end
    end
    return names
end

--- The recipe a file belongs to, so that a task runs against the recipe you are
--- looking at. An append, an include and a recipe file all answer.
---@param path string?
---@return string?
function M.owning(path)
    path = path or vim.api.nvim_buf_get_name(0)
    if not path or path == '' then
        return nil
    end

    local extension = vim.fn.fnamemodify(path, ':e')
    if extension ~= 'bb' and extension ~= 'bbappend' and extension ~= 'inc' then
        return nil
    end

    -- The index of the project the file belongs to, which is not necessarily the
    -- project the current buffer is in.
    local name = split_name(path)
    for _, recipe in ipairs(M.list(project.root(path))) do
        if recipe.name == name then
            return name
        end
    end
    return nil
end

return M
