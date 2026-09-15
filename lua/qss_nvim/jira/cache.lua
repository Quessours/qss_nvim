-- Every answer here costs a network round trip, so the picker would open on an
-- empty list and fill in a second later. The store survives a restart because
-- the two slowest lookups, the account id and the numeric id of an issue, never
-- change once they are known.
local M = {}

local PATH = vim.fs.joinpath(vim.fn.stdpath('cache'), 'qss_jira.json')

---@class qss.jira.Entry
---@field value any
---@field expires_at integer? absent for an entry that never goes stale

---@type table<string, qss.jira.Entry>?
local entries

---@return table<string, qss.jira.Entry>
local function load()
    if entries then
        return entries
    end
    entries = {}

    local file = io.open(PATH, 'r')
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
    local file = io.open(PATH, 'w')
    if not file then
        return
    end
    file:write(vim.json.encode(entries or {}))
    file:close()
end

--- The value behind a key, as long as it has not gone stale.
---@param key string
---@return any
function M.get(key)
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
function M.set(key, value, ttl)
    load()[key] = { value = value, expires_at = ttl and os.time() + ttl or nil }
    save()
end

--- Forget one key. Every picker binds this to <C-r>.
---@param key string
function M.invalidate(key)
    if load()[key] then
        entries[key] = nil
        save()
    end
end

--- Forget every key that starts with a prefix.
---@param prefix string
function M.invalidate_prefix(prefix)
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

return M
