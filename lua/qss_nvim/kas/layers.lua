-- The layers of the current build, which is where every recipe and every task
-- description is read from.
--
-- kas writes bblayers.conf when it checks the project out, and BBLAYERS in that
-- file is the exact set bitbake parses. It is also the cheapest answer there is,
-- one file read, so it is the one used. The paths in it are container paths
-- under kas-container, so each one goes back through the mount list.

local cache = require('qss_nvim.cache').store('qss_kas')
local project = require('qss_nvim.kas.project')

local M = {}

-- Only the fallback scan is cached. Reading bblayers.conf is one file read, so
-- it happens every time and a changed layer list is picked up at once.
local SCAN_TTL = 24 * 60 * 60

---@param path string
---@return boolean
local function is_layer(path)
    return vim.fn.filereadable(path .. '/conf/layer.conf') == 1
end

--- One BBLAYERS entry as a path on this machine.
---
--- bitbake expands the file before it reads it, and kas writes the entries
--- relative to ${TOPDIR}: "${TOPDIR}/../work/layers/poky/meta". TOPDIR is the
--- build directory as the build sees it, which under kas-container is /build,
--- so the expansion has to happen in container space and the `..` has to be
--- resolved before the path can be mapped back here.
---@param root string
---@param entry string
---@param topdir string
---@return string? host
---@return string? unresolved the variable that could not be expanded
local function to_layer_path(root, entry, topdir)
    local expanded = entry:gsub('%${TOPDIR}', topdir)

    local variable = expanded:match('%${[%w_]+}')
    if variable then
        return nil, variable
    end
    return project.to_host(vim.fs.normalize(expanded), root), nil
end

--- BBLAYERS, as the build directory has it. A line continuation inside the
--- quoted value is normal in that file, so the whole thing is read as one
--- string before the assignments are matched, and a layer list built up over
--- several statements is concatenated.
---@param root string
---@return string[] roots
---@return string[] unresolved
local function from_bblayers_conf(root)
    local path = M.bblayers_conf(root)
    local build = project.build_dir(root)
    if not path or not build then
        return {}, {}
    end

    local topdir = project.to_container(build, root)
    local contents = table.concat(vim.fn.readfile(path), '\n'):gsub('\\\n', ' ')

    local roots = {}
    local unresolved = {}
    local seen = {}

    for value in contents:gmatch('BBLAYERS%s*[?:+]*=%s*"(.-)"') do
        for entry in value:gmatch('%S+') do
            local host, variable = to_layer_path(root, entry, topdir)
            if variable then
                unresolved[#unresolved + 1] = variable
            elseif host and is_layer(host) and not seen[host] then
                seen[host] = true
                roots[#roots + 1] = host
            end
        end
    end
    return roots, unresolved
end

--- Every layer in the checkout, for a project that has not been checked out
--- into a build directory yet. tmp, downloads and sstate-cache hold millions of
--- files between them, so the scan never descends into any of the three.
---@param root string
---@return string[]
local function from_checkout(root)
    local found = vim.fn.systemlist({
        'find', root, '-maxdepth', '6',
        '(', '-name', 'tmp', '-o', '-name', 'downloads', '-o', '-name', 'sstate-cache',
        '-o', '-name', '.git', ')', '-prune',
        '-o', '-path', '*/conf/layer.conf', '-print',
    })
    if vim.v.shell_error ~= 0 then
        return {}
    end

    local roots = {}
    for _, path in ipairs(found) do
        roots[#roots + 1] = vim.fs.dirname(vim.fs.dirname(path))
    end
    table.sort(roots)
    return roots
end

--- The bblayers.conf of the build, when there is one.
---@param root string?
---@return string?
function M.bblayers_conf(root)
    root = root or project.root()
    local build = root and project.build_dir(root)
    if not build then
        return nil
    end

    local path = build .. '/conf/bblayers.conf'
    if vim.fn.filereadable(path) == 0 then
        return nil
    end
    return path
end

--- The layer roots of the project, as absolute host paths.
---@param root string? project root
---@param opts { refresh: boolean? }?
---@return string[]
function M.roots(root, opts)
    root = root or project.root()
    if not root then
        return {}
    end

    local roots, unresolved = from_bblayers_conf(root)

    -- What bblayers.conf named and this could not expand. :KasDoctor reports it,
    -- because the layer list is silently a different one when it happens.
    ---@type string[]
    M.unresolved = unresolved

    if #roots > 0 then
        return roots
    end

    -- Nothing usable in bblayers.conf, so every layer in the checkout is
    -- offered instead. That scan walks the whole project, which is why its
    -- answer is the one that gets cached.

    local key = cache.key(root, 'layer_scan')
    if (opts or {}).refresh then
        cache.invalidate(key)
    else
        local remembered = cache.get(key)
        if remembered then
            return remembered
        end
    end

    local scanned = from_checkout(root)
    if #scanned > 0 then
        cache.set(key, scanned, SCAN_TTL)
    end
    return scanned
end

---@param path string
---@return integer
local function mtime(path)
    local stat = vim.uv.fs_stat(path)
    if not stat then
        return 0
    end
    return stat.mtime.sec
end

--- What changes when the layers change.
---
--- A checkout rewrites the git index of the repository it touched, and kas
--- rewrites bblayers.conf, so those mtimes together say whether an index built
--- earlier can still be trusted. It costs a handful of stat calls, which is why
--- it can run on the way into a picker.
---@param root string?
---@return string
function M.fingerprint(root)
    root = root or project.root()
    if not root then
        return ''
    end

    local parts = { tostring(mtime(M.bblayers_conf(root) or '')) }
    for _, layer in ipairs(M.roots(root)) do
        -- The layer is either the repository or a directory inside it.
        local git = vim.fs.find('.git', { path = layer, upward = true, type = 'directory' })[1]
        local stamp = mtime(layer)
        if git then
            stamp = math.max(mtime(git .. '/index'), mtime(git .. '/HEAD'))
        end
        parts[#parts + 1] = ('%s@%d'):format(vim.fs.basename(layer), stamp)
    end
    return table.concat(parts, ' ')
end

--- The bitbake directory itself, the one holding lib/bb. The bitbake language
--- server reads the variable and task definitions out of it.
---@param root string?
---@return string?
function M.bitbake_dir(root)
    for _, layer in ipairs(M.roots(root)) do
        local candidate = vim.fs.dirname(layer) .. '/bitbake'
        if vim.fn.isdirectory(candidate .. '/lib/bb') == 1 then
            return candidate
        end
    end
    return nil
end

--- Every readable file of one name across the layers, in layer order.
---@param relative string a path below the layer root, such as "conf/documentation.conf"
---@param root string?
---@return string[]
function M.files(relative, root)
    local paths = {}
    for _, layer in ipairs(M.roots(root)) do
        local path = layer .. '/' .. relative
        if vim.fn.filereadable(path) == 1 then
            paths[#paths + 1] = path
        end
    end
    return paths
end

---@class qss.kas.Class
---@field name string
---@field layer string

---@type table<string, qss.kas.Class[]>
local classes_of = {}

--- The bbclass files of the layers, which is what `inherit` takes. Poky splits
--- them over classes, classes-global and classes-recipe.
---@param root string?
---@return qss.kas.Class[]
function M.classes(root)
    root = root or project.root()
    if not root then
        return {}
    end

    local remembered = classes_of[root]
    if remembered then
        return remembered
    end

    local classes = {}
    local seen = {}
    for _, layer in ipairs(M.roots(root)) do
        for _, path in ipairs(vim.fn.glob(layer .. '/classes*/*.bbclass', true, true)) do
            local name = vim.fn.fnamemodify(path, ':t:r')
            if not seen[name] then
                seen[name] = true
                classes[#classes + 1] = { name = name, layer = layer }
            end
        end
    end

    table.sort(classes, function(a, b)
        return a.name < b.name
    end)
    classes_of[root] = classes
    return classes
end

return M
