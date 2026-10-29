-- State that would otherwise reach disk only when nvim exits.
--
-- Each entry is compared, not hooked: its snapshot is taken again whenever the
-- editor goes idle or loses focus, and saved when it differs from the last one.
-- A picker sets its value in a callback some time after its command returned,
-- and comparing catches that, as well as every path that was never wrapped.

local M = {}

---@class qss.persist.Entry
---@field name string shown in the warning when saving fails
---@field snapshot fun(): string the saved state, encoded so that equal means unchanged
---@field save fun()

---@type qss.persist.Entry[]
local entries = {}

---@type table<string, string?>
local saved = {}

local group

---@param entry qss.persist.Entry
local function persist(entry)
    local ok, current = pcall(entry.snapshot)
    if not ok or current == saved[entry.name] then
        return
    end
    -- Recorded even when the save fails, so that a broken save warns once per
    -- change instead of on every idle tick.
    saved[entry.name] = current

    local saved_ok, err = pcall(entry.save)
    if not saved_ok then
        vim.notify(('could not save the %s state: %s'):format(entry.name, err),
            vim.log.levels.WARN, { title = 'Persist' })
    end
end

--- Save every entry whose state changed since its last save.
function M.flush()
    for _, entry in ipairs(entries) do
        persist(entry)
    end
end

--- Take the state as it is now as already saved, for instance right after it
--- was loaded from disk.
---@param name string
function M.reset(name)
    for _, entry in ipairs(entries) do
        if entry.name == name then
            local ok, current = pcall(entry.snapshot)
            saved[name] = ok and current or nil
        end
    end
end

--- Start watching an entry. Its current state counts as saved.
---@param entry qss.persist.Entry
function M.register(entry)
    table.insert(entries, entry)
    M.reset(entry.name)

    if group then
        return
    end
    group = vim.api.nvim_create_augroup('qss_persist', { clear = true })
    vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI', 'FocusLost' }, {
        group = group,
        callback = M.flush,
    })
end

return M
