-- Answers that cost something to work out, kept on disk.
--
-- A store outlives the session because the answers in it are choices, or facts
-- that only change when the project does. Everything is keyed by project root,
-- so two checkouts never read each other's entries.
--
-- Each store is one JSON file named after it. Two modules asking for the same
-- name get the same store: a second instance would hold its own copy of the
-- file in memory and overwrite whatever the first one wrote.

local M = {}

---@class qss.cache.Entry
---@field value any
---@field expires_at integer? absent for an entry that never goes stale

---@class qss.cache.Store
---@field key fun(root: string, ...: string): string
---@field get fun(key: string): any
---@field set fun(key: string, value: any, ttl: integer?)
---@field invalidate fun(key: string)
---@field invalidate_prefix fun(prefix: string)

---@type table<string, qss.cache.Store>
local stores = {}

--- The store named `name`, backed by stdpath('cache')/<name>.json.
---@param name string
---@return qss.cache.Store
function M.store(name)
    if stores[name] then
        return stores[name]
    end

    local path = vim.fs.joinpath(vim.fn.stdpath('cache'), name .. '.json')

    ---@type table<string, qss.cache.Entry>?
    local entries

    ---@return table<string, qss.cache.Entry>
    local function load()
        if entries then
            return entries
        end
        entries = {}

        local file = io.open(path, 'r')
        if not file then
            return entries
        end
        local contents = file:read('*a')
        file:close()

        local ok, decoded = pcall(vim.json.decode, contents)
        if ok and type(decoded) == 'table' then
            entries = decoded
        end
        return entries
    end

    local function save()
        local file = io.open(path, 'w')
        if not file then
            return
        end
        file:write(vim.json.encode(entries or {}))
        file:close()
    end

    local store = {}

    --- The key one project's answer lives under.
    ---@param root string
    ---@param ... string
    ---@return string
    function store.key(root, ...)
        return table.concat({ root, ... }, ':')
    end

    --- The value behind a key, as long as it has not gone stale.
    ---@param key string
    ---@return any
    function store.get(key)
        local entry = load()[key]
        if not entry then
            return nil
        end
        if entry.expires_at and entry.expires_at < os.time() then
            return nil
        end
        return entry.value
    end

    --- Remember a value. Leave `ttl` out for something that never changes.
    ---@param key string
    ---@param value any
    ---@param ttl integer? seconds
    function store.set(key, value, ttl)
        load()[key] = { value = value, expires_at = ttl and os.time() + ttl or nil }
        save()
    end

    --- Forget one key. Every picker binds this to <C-r>.
    ---@param key string
    function store.invalidate(key)
        if load()[key] then
            entries[key] = nil
            save()
        end
    end

    --- Forget every key that starts with a prefix.
    ---@param prefix string
    function store.invalidate_prefix(prefix)
        local removed = false
        for key in pairs(load()) do
            if key:sub(1, #prefix) == prefix then
                entries[key] = nil
                removed = true
            end
        end
        if removed then
            save()
        end
    end

    stores[name] = store
    return store
end

return M
