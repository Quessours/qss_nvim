-- Which unversioned files are worth reaching, and which are only noise.
--
-- A .gitignore says "do not commit this", not "never show me this", and every
-- search tool filters on the first as though it meant the second. That hides
-- the per-project files which exist precisely because they are not versioned: a
-- CMakeUserPresets.json, a bitbake local.conf, a kas local.yml, the .nvim.lua
-- that init.lua reads through exrc. Showing everything git ignores instead
-- drowns the list: on the Yocto tree here, 3.17 million files against 438, and
-- thirteen seconds against eleven milliseconds.
--
-- So neither switch is the answer, and the answer is not one list either. Each
-- kind of project has its own handful of local files and its own build
-- directories, so they are declared here per kind and the consumers take the
-- union. Adding a project kind is one entry below and nothing else.
--
-- `server` names the language server that goes with the kind, to keep this list
-- next to the one in lsp_init.lua. It is not the discriminator: a local file
-- belongs to a build system rather than to a server, CMakeUserPresets.json
-- being CMake's while clangd also serves a plain Makefile tree. `markers` is
-- what actually says a directory is of that kind.

local M = {}

---@class qss.LocalFiles.Kind
---@field server string? the language server this kind is usually edited with
---@field markers string[] globs that say a directory is a project of this kind
---@field files string[] names or globs of the local files worth always showing
---@field reach string[]? directories that must stay visible to get to those files
---@field noise string[]? directories that are never worth walking into

---@type table<string, qss.LocalFiles.Kind>
M.kinds = {
    -- Anything, whatever the language.
    any = {
        markers = { '.git' },
        files = { '.nvim.lua', '.nvimrc', '.env', '.envrc', '.env.local' },
        noise = { '.git', '.cache', '.direnv' },
    },

    cmake = {
        server = 'clangd',
        markers = { 'CMakeLists.txt', 'CMakePresets.json' },
        -- The local half of the presets file, which is the documented place for
        -- a developer's own configure and build presets and is gitignored by
        -- convention.
        files = { 'CMakeUserPresets.json', 'CMakeSettings.json' },
        noise = { 'CMakeFiles', '_deps', 'cmake-build-*' },
    },

    qmake = {
        server = 'qmlls',
        markers = { '*.pro' },
        -- What Qt Creator writes beside a .pro file: paths and kits of one
        -- machine, never committed.
        files = { '*.pro.user' },
    },

    kas = {
        server = 'bitbakels',
        markers = { 'kas*.yml', 'kas/*.yml', '.config.yaml' },
        files = { 'local.conf', 'site.conf', 'auto.conf', 'local.yml' },
        -- bitbake keeps its configuration inside the build directory, so the
        -- way down to it has to stay visible even though git ignores the lot.
        reach = { 'build', 'build/conf' },
        noise = { 'tmp', 'tmp-*', 'sstate-cache', 'downloads', 'buildhistory*' },
    },

    rust = {
        server = 'rust-analyzer',
        markers = { 'Cargo.toml' },
        -- Named with its directory, because a bare config.toml is too common a
        -- name to force open wherever it appears.
        files = { '.cargo/config.toml' },
        reach = { '.cargo' },
        noise = { 'target' },
    },

    python = {
        server = 'pyright',
        markers = { 'pyproject.toml', 'setup.py', 'requirements.txt' },
        files = { '.env' },
        noise = { '.venv', 'venv', '__pycache__', '.mypy_cache', '.pytest_cache', '.ruff_cache' },
    },

    node = {
        server = 'ts_ls',
        markers = { 'package.json' },
        files = { '.env.local', '.env.development.local' },
        noise = { 'node_modules', 'dist', '.next', '.turbo' },
    },

    zig = {
        server = 'zls',
        markers = { 'build.zig' },
        files = {},
        noise = { 'zig-cache', '.zig-cache', 'zig-out' },
    },
}

---@param field string
---@return string[]
local function union(field)
    local seen = {}
    local values = {}

    -- A stable order, because these end up in a command line.
    local names = vim.tbl_keys(M.kinds)
    table.sort(names)

    for _, name in ipairs(names) do
        for _, value in ipairs(M.kinds[name][field] or {}) do
            if not seen[value] then
                seen[value] = true
                values[#values + 1] = value
            end
        end
    end
    return values
end

--- Every directory that has to stay visible, as a set of its components: the
--- kas entry "build/conf" protects "build" as well.
---@return table<string, boolean>
local function reachable()
    local components = {}
    for _, path in ipairs(union('reach')) do
        for component in path:gmatch('[^/]+') do
            components[component] = true
        end
    end
    return components
end

--- The build directories, as globs for ripgrep and fd. A directory something
--- else has to reach through is never excluded, whichever kind asked for it.
---@return string[]
function M.picker_exclude()
    local keep = reachable()
    return vim.tbl_filter(function(glob)
        return not keep[glob]
    end, union('noise'))
end

---@param text string
---@return string
local function escape_lua(text)
    return (text:gsub('([%^%$%(%)%%%.%[%]%+%-%?])', '%%%1'))
end

--- A glob as a Lua pattern that matches the end of an absolute path. "*" stops
--- at a path separator, the way a shell glob does.
---@param glob string
---@return string
local function to_lua_pattern(glob)
    local pattern = escape_lua(glob):gsub('%*', '[^/]*')
    return '/' .. pattern .. '$'
end

--- What nvim-tree matches against the absolute path of a node, for
--- filters.exclude. An entry there overrides every other filter, the gitignore
--- one included, which is the only way a local.conf below an ignored build
--- directory can be reached at all.
---@return string[]
function M.tree_patterns()
    local patterns = {}
    for _, path in ipairs(union('reach')) do
        patterns[#patterns + 1] = '/' .. escape_lua(path) .. '$'
    end
    for _, name in ipairs(union('files')) do
        patterns[#patterns + 1] = to_lua_pattern(name)
    end
    return patterns
end

--- The same globs as vim regexes, for filters.custom.
---
--- This is the other half of the exclusion above, and it is not optional: git
--- reports an ignored directory and not the files inside it, so forcing "build"
--- open shows every object file under it. nvim-tree consults filters.custom for
--- those children, which is where the build directories get hidden again.
---@return string[]
function M.tree_custom()
    local keep = reachable()
    local patterns = {}

    for _, glob in ipairs(union('noise')) do
        if not keep[glob] then
            patterns[#patterns + 1] = '^' .. glob:gsub('([%.%\\])', '\\%1'):gsub('%*', '.*') .. '$'
        end
    end
    return patterns
end

--- Which kinds a directory looks like, for a report or a health check.
---@param dir string?
---@return string[]
function M.kinds_of(dir)
    dir = dir or vim.uv.cwd() or '.'

    local found = {}
    for name, kind in pairs(M.kinds) do
        for _, marker in ipairs(kind.markers) do
            if #vim.fn.glob(dir .. '/' .. marker, true, true) > 0 then
                found[#found + 1] = name
                break
            end
        end
    end
    table.sort(found)
    return found
end

return M
