-- Where the cargo project is.
--
-- The nearest Cargo.toml wins, not the outermost. A workspace member is a crate
-- in its own right, and cargo metadata reports which workspace it belongs to,
-- so the climb never has to guess at one. Taking the outermost instead would
-- also join two unrelated crates that happen to share a parent directory.

local M = {}

---@type table<string, string|false>
local root_of = {}

---@param dir string
---@return boolean
function M.is_cargo_project(dir)
    return vim.fn.filereadable(dir .. '/Cargo.toml') == 1
end

---@param start string a directory
---@return string?
local function climb(start)
    local cached = root_of[start]
    if cached ~= nil then
        return cached or nil
    end

    ---@type string|false
    local found = false
    local dir = start

    while dir and dir ~= '' do
        if M.is_cargo_project(dir) then
            found = dir
            break
        end

        local parent = vim.fs.dirname(dir)
        if parent == dir then
            break
        end
        dir = parent
    end

    root_of[start] = found
    return found or nil
end

--- The crate directory a path belongs to.
---
--- With no argument the directory nvim runs in decides, the way the cmake and
--- kas modules here take it, and the buffer is only the fallback for a session
--- started outside any project. A dependency opened out of the registry
--- therefore does not move the project, and neither does a task output buffer.
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

return M
