-- <CR> in the output of a task opens the file location on the line under the
-- cursor, in a window that holds a file.
--
-- The location is read from the output text, so it works for any compiler that
-- prints "path:line:col": gcc and clang put it on the message line, and rustc
-- puts it on the next one (" --> src/main.rs:3:5"). Any other line is left
-- alone, so that <CR> on a line with no location never opens a nearby one.
--
-- A path in the output is not always a path here: kas prints container paths
-- and a CMake build prints paths relative to the build directory. The parsed
-- items of the task already hold the right path for those (qss_kas_paths,
-- relative_file_root), so an item on the same line number and file name wins.
-- Otherwise the path is tried as is, then from the task directory and each of
-- its parents, which covers a cargo workspace member.

local task_list = require('overseer.task_list')

local M = {}

local RUSTC_ARROW = '^%s*%-%->'

local LOCATION = '([%w%._/%-+~]+):(%d+):?(%d*)'

---@class qss.overseer.Location
---@field filename string
---@field lnum integer
---@field col integer?

--- The parsed item of the task that a location in the output names.
---@param task table
---@param path string
---@param lnum integer
---@return string? filename
local function parsed_filename(task, path, lnum)
    local items = task.result and task.result.diagnostics or {}
    local name = vim.fs.basename(path)
    for _, item in ipairs(items) do
        if item.filename and item.lnum == lnum and vim.fs.basename(item.filename) == name then
            return item.filename
        end
    end
end

--- The file on this machine that a path in the output names.
---@param task table
---@param path string
---@return string?
local function existing_file(task, path)
    if path:sub(1, 1) == '/' then
        return vim.fn.filereadable(path) == 1 and path or nil
    end
    local dir = task.cwd or vim.fn.getcwd()
    for _, base in ipairs(vim.list_extend({ dir }, vim.iter(vim.fs.parents(dir)):totable())) do
        local candidate = vim.fs.joinpath(base, path)
        if vim.fn.filereadable(candidate) == 1 then
            return candidate
        end
    end
end

---@param task table
---@param line string
---@return qss.overseer.Location?
local function location_in(task, line)
    for path, lnum, col in line:gmatch(LOCATION) do
        local line_number = tonumber(lnum) --[[@as integer]]
        local filename = parsed_filename(task, path, line_number) or existing_file(task, path)
        if filename then
            return { filename = filename, lnum = line_number, col = tonumber(col) }
        end
    end
end

---@param task table
---@param bufnr integer
---@param row integer 1-based
---@return qss.overseer.Location?
local function location_near(task, bufnr, row)
    local lines = vim.api.nvim_buf_get_lines(bufnr, row - 1, row + 1, false)
    local found = location_in(task, lines[1])
    if found then
        return found
    end
    if lines[2] and lines[2]:match(RUSTC_ARROW) then
        return location_in(task, lines[2])
    end
end

--- The window to show a source file in: the previous one if it holds a file,
--- else the first one in the tab that does, else a new one above the rest.
---@return integer
local function file_window()
    local function holds_file(win)
        return vim.api.nvim_win_is_valid(win) and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
    end

    local previous = vim.fn.win_getid(vim.fn.winnr('#'))
    if previous ~= 0 and holds_file(previous) then
        return previous
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if holds_file(win) then
            return win
        end
    end
    vim.cmd('topleft split')
    return vim.api.nvim_get_current_win()
end

---@param location qss.overseer.Location
local function open(location)
    local bufnr = vim.fn.bufadd(location.filename)
    vim.fn.bufload(bufnr)
    local win = file_window()
    vim.api.nvim_win_set_buf(win, bufnr)
    vim.api.nvim_set_current_win(win)

    local lnum = math.min(location.lnum, vim.api.nvim_buf_line_count(bufnr))
    local col = math.max((location.col or 1) - 1, 0)
    vim.api.nvim_win_set_cursor(win, { math.max(lnum, 1), col })
end

---@param bufnr integer
local function jump(bufnr)
    local task = task_list.get(vim.b[bufnr].overseer_task)
    if not task then
        return
    end
    local location = location_near(task, bufnr, vim.api.nvim_win_get_cursor(0)[1])
    if not location then
        vim.notify('No file location on this line', vim.log.levels.INFO)
        return
    end
    open(location)
end

function M.setup()
    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'OverseerOutput',
        desc = 'Jump from the output of a task to a file location in it',
        callback = function(args)
            vim.keymap.set('n', '<CR>', function()
                jump(args.buf)
            end, { buffer = args.buf, desc = 'Open the location' })
        end,
    })
end

return M
