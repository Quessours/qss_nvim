-- Which preset file sets a cache variable, and writing a new value back into it.
--
-- `cmake --preset` passes every cacheVariables entry as a -D on each configure,
-- so a value put in the cache by hand only lasts until the next configure run.
-- The one place an edit sticks is the preset itself. cmake-tools merges all the
-- files into one list and forgets where each preset came from, which is the one
-- thing this needs, so the files are read again here.

local M = {}

local USER_FILE = 'CMakeUserPresets.json'
local SHARED_FILE = 'CMakePresets.json'

---@class qss.cmake.RawPreset
---@field name string
---@field file string absolute path of the file that declares it
---@field user boolean declared in CMakeUserPresets.json, which is not checked in
---@field inherits string[]
---@field cache table<string, any>

---@param path string
---@return table?
local function decode(path)
    local file = io.open(path, 'r')
    if not file then
        return nil
    end
    local text = file:read('*a')
    file:close()
    local ok, data = pcall(vim.json.decode, text)
    return ok and type(data) == 'table' and data or nil
end

--- The file, then its `include` list, depth first. CMakeUserPresets.json
--- includes CMakePresets.json without saying so.
---@param path string
---@param index table<string, qss.cmake.RawPreset>
---@param visited table<string, boolean>
local function read(path, index, visited)
    path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
    if visited[path] then
        return
    end
    visited[path] = true

    local data = decode(path)
    if not data then
        return
    end

    local user = vim.fs.basename(path) == USER_FILE
    for _, preset in ipairs(data.configurePresets or {}) do
        local inherits = preset.inherits
        if type(inherits) == 'string' then
            inherits = { inherits }
        end
        index[preset.name] = index[preset.name] or {
            name = preset.name,
            file = path,
            user = user,
            inherits = inherits or {},
            cache = type(preset.cacheVariables) == 'table' and preset.cacheVariables or {},
        }
    end

    local dir = vim.fs.dirname(path)
    local includes = data.include or {}
    if user and #includes == 0 then
        includes = { SHARED_FILE }
    end
    for _, include in ipairs(includes) do
        include = include:gsub('%$penv{(.-)}', function(name)
            return vim.env[name] or ''
        end)
        if not vim.startswith(include, '/') then
            include = dir .. '/' .. include
        end
        read(include, index, visited)
    end
end

---@param root string
---@return table<string, qss.cmake.RawPreset>
local function index_presets(root)
    local index, visited = {}, {}
    read(root .. '/' .. USER_FILE, index, visited)
    read(root .. '/' .. SHARED_FILE, index, visited)
    return index
end

---@class qss.cmake.PresetValue
---@field preset qss.cmake.RawPreset the preset whose cacheVariables holds it
---@field raw any the value as the JSON holds it: a string, a boolean or a {type, value} object

--- The preset itself first, then each parent in the order `inherits` lists them,
--- which is the order cmake resolves a variable in. A null stops the search: it
--- removes what a parent set.
---@param index table<string, qss.cmake.RawPreset>
---@param name string
---@param variable string
---@param seen table<string, boolean>
---@return qss.cmake.PresetValue?, boolean found
local function lookup(index, name, variable, seen)
    local preset = index[name]
    if not preset or seen[name] then
        return nil, false
    end
    seen[name] = true

    local raw = preset.cache[variable]
    if raw == vim.NIL then
        return nil, true
    end
    if raw ~= nil then
        return { preset = preset, raw = raw }, true
    end
    for _, parent in ipairs(preset.inherits) do
        local value, found = lookup(index, parent, variable, seen)
        if found then
            return value, true
        end
    end
    return nil, false
end

---@class qss.cmake.PresetOwners
---@field selected qss.cmake.RawPreset
---@field values table<string, qss.cmake.PresetValue> the variables a preset in the chain sets

---@param preset_name string
---@return qss.cmake.PresetOwners?
function M.owners(preset_name)
    local index = index_presets(vim.fn.getcwd())
    local selected = index[preset_name]
    if not selected then
        return nil
    end

    local names = {}
    local function collect(name, seen)
        local preset = index[name]
        if not preset or seen[name] then
            return
        end
        seen[name] = true
        for variable in pairs(preset.cache) do
            names[variable] = true
        end
        for _, parent in ipairs(preset.inherits) do
            collect(parent, seen)
        end
    end
    collect(preset_name, {})

    local values = {}
    for variable in pairs(names) do
        values[variable] = lookup(index, preset_name, variable, {})
    end
    return { selected = selected, values = values }
end

--- The indent the file already uses, so that a rewrite changes the edited lines
--- and nothing else. jq keeps the key order.
---@param text string
---@return string[]
local function indent_args(text)
    local indent = text:match('\n([ \t]+)%S')
    if indent and indent:find('\t', 1, true) then
        return { '--tab' }
    end
    return { '--indent', tostring(indent and #indent or 2) }
end

--- An entry in the object form keeps its type and only gets a new value.
local SET_EXPR = [[
reduce $edits[] as $e (.;
  (.configurePresets[] | select(.name == $e.preset) | .cacheVariables[$e.name]) |=
    (if type == "object" then .value = $e.value else $e.value end))
]]

---@class qss.cmake.PresetEdit
---@field preset string
---@field name string
---@field value any string or boolean, as it goes into the JSON

---@param file string
---@param edits qss.cmake.PresetEdit[]
---@return boolean ok, string? err
function M.write(file, edits)
    local handle = io.open(file, 'r')
    if not handle then
        return false, 'cannot read ' .. file
    end
    local text = handle:read('*a')
    handle:close()

    local cmd = { 'jq' }
    vim.list_extend(cmd, indent_args(text))
    vim.list_extend(cmd, { '--argjson', 'edits', vim.json.encode(edits), SET_EXPR })
    local result = vim.system(cmd, { stdin = text, text = true }):wait()
    if result.code ~= 0 then
        return false, vim.trim(result.stderr or '')
    end

    handle = io.open(file, 'w')
    if not handle then
        return false, 'cannot write ' .. file
    end
    handle:write(result.stdout)
    handle:close()
    return true
end

return M
