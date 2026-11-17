-- What a failed ninja build says, without the rest of its output.
--
-- Ninja prints the output of a failed step as one block: a `FAILED: <outputs>`
-- line, the command line, then what the command printed. The block ends at the
-- next status line (`[12/345] ...`) or at the `ninja: build stopped` line. A
-- large build buries those blocks under thousands of lines of progress and of
-- messages that fail nothing, such as the `Info:` hints of qmllint, so the one
-- warning that stopped the build is the hardest line to find.
--
-- The qss_build_failures component feeds the output here while the build runs.
-- When the build fails, the problems go to the quickfix list and to a "build
-- problems" task, whose output lists them by type: errors, then warnings, then
-- the lines with no file location. A notification would disappear before you
-- read it, and the task stays in the list until you dispose of it.

local M = {}

local REPORT = 'build problems'

---@class qss.BuildFailure
---@field target string the first output of the failed step
---@field items vim.quickfix.entry[] the problems it reported at a file location
---@field others string[] the problems it reported with no file location

---@param line string
---@return string
local function clean(line)
    local without_colors = line:gsub('\27%[[%d;]*[A-Za-z]', '')
    return (without_colors:gsub('\r$', ''))
end

---@param line string
---@return boolean
local function ends_block(line)
    return line:match('^%[%d+/%d+%]') ~= nil or line:match('^ninja: ') ~= nil
end

---@param line string
---@return string? target
local function failed_target(line)
    local outputs = line:match('^FAILED: (.*)$')
    if not outputs then
        return nil
    end
    -- Ninja 1.12 and later put the exit code first: "FAILED: [code=1] out".
    outputs = outputs:gsub('^%[code=%d+%]%s*', '')
    return vim.fs.basename(outputs:match('^(%S+)') or outputs)
end

---@param path string
---@param root string?
---@return string
local function resolve(path, root)
    if path:sub(1, 1) == '/' or not root then
        return path
    end
    return vim.fs.normalize(vim.fs.joinpath(root, path))
end

-- The levels at which qmllint makes its target fail. Its "Info:" lines are
-- hints about compiling QML to C++.
local QMLLINT_TYPES = { Warning = 'W', Critical = 'E', Error = 'E' }

--- A quickfix item for a line that reports a problem at a file location.
---@param line string
---@param root string?
---@return vim.quickfix.entry?
local function located_problem(line, root)
    local level, path, lnum, col, text = line:match('^(%a+): (.-):(%d+):(%d+): (.*)$')
    if level and QMLLINT_TYPES[level] then
        return {
            filename = resolve(path, root),
            lnum = tonumber(lnum),
            col = tonumber(col),
            type = QMLLINT_TYPES[level],
            text = text,
        }
    end

    local kind
    path, lnum, col, kind, text = line:match('^(.-):(%d+):(%d+): ([%a ]-): (.*)$')
    if not kind then
        return nil
    end
    local is_error = kind:find('error') ~= nil
    if not is_error and not kind:find('warning') then
        return nil
    end
    return {
        filename = resolve(path, root),
        lnum = tonumber(lnum),
        col = tonumber(col),
        type = is_error and 'E' or 'W',
        text = text,
    }
end

--- A line with no file location that still reports a problem, such as a
--- linker error.
---@param line string
---@return boolean
local function unlocated_problem(line)
    local lower = line:lower()
    return lower:find('error') ~= nil or lower:find('undefined reference') ~= nil
end

---@class qss.BuildFailureCollector
---@field root string? where relative paths in the output start from
---@field current { target: string, lines: string[] }?
---@field blocks { target: string, lines: string[] }[]
local Collector = {}
Collector.__index = Collector

---@param root string?
---@return qss.BuildFailureCollector
function M.collector(root)
    return setmetatable({ root = root, blocks = {} }, Collector)
end

---@param raw string
function Collector:feed(raw)
    local line = clean(raw)
    local target = failed_target(line)
    if target then
        self.current = { target = target, lines = {} }
        table.insert(self.blocks, self.current)
    elseif self.current and ends_block(line) then
        self.current = nil
    elseif self.current and vim.trim(line) ~= '' then
        table.insert(self.current.lines, line)
    end
end

---@return qss.BuildFailure[]
function Collector:failures()
    local result = {}
    for _, block in ipairs(self.blocks) do
        local failure = { target = block.target, items = {}, others = {} }
        for _, line in ipairs(block.lines) do
            local item = located_problem(line, self.root)
            if item then
                table.insert(failure.items, item)
            elseif unlocated_problem(line) then
                table.insert(failure.others, vim.trim(line))
            end
        end
        -- A step can fail without a line that says why. Its last line is then
        -- the best clue left.
        if #failure.items == 0 and #failure.others == 0 and #block.lines > 0 then
            table.insert(failure.others, vim.trim(block.lines[#block.lines]))
        end
        table.insert(result, failure)
    end
    return result
end

---@param failures qss.BuildFailure[]
---@return vim.quickfix.entry[]
local function all_items(failures)
    local items = {}
    for _, failure in ipairs(failures) do
        vim.list_extend(items, failure.items)
    end
    return items
end

--- The quickfix list holds the located problems of the failed steps.
---@param failures qss.BuildFailure[]
function M.to_quickfix(failures)
    local items = all_items(failures)
    if #items == 0 then
        return
    end
    vim.fn.setqflist({}, ' ', { title = 'Build failures', items = items })
end

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@return boolean
local function by_place(a, b)
    if a.filename ~= b.filename then
        return a.filename < b.filename
    end
    if a.lnum ~= b.lnum then
        return a.lnum < b.lnum
    end
    return (a.col or 0) < (b.col or 0)
end

--- A line in the "file:line:col: level: message" shape, which log_colors.lua
--- colors by level and where <CR> opens the file. The path is relative to the
--- directory nvim runs in when the file is under it, to keep the line short.
---@param item vim.quickfix.entry
---@param level string
---@return string
local function located_line(item, level)
    return ('%s:%d:%d: %s: %s'):format(vim.fn.fnamemodify(item.filename, ':.'), item.lnum,
        item.col or 0, level, item.text)
end

---@param lines string[]
---@param heading string
---@param entries string[]
local function add_section(lines, heading, entries)
    if #entries == 0 then
        return
    end
    table.insert(lines, '')
    table.insert(lines, ('%s (%d)'):format(heading, #entries))
    for _, entry in ipairs(entries) do
        table.insert(lines, '  ' .. entry)
    end
end

--- The report: the failed steps, then their problems by type, each type
--- sorted by file and line.
---@param failures qss.BuildFailure[]
---@return string[]
function M.render(failures)
    local targets = vim.tbl_map(function(failure)
        return failure.target
    end, failures)
    local lines = {
        ('%d failed step%s: %s'):format(#failures, #failures == 1 and '' or 's',
            table.concat(targets, ', ')),
    }

    local items = all_items(failures)
    table.sort(items, by_place)
    local errors, warnings = {}, {}
    for _, item in ipairs(items) do
        if item.type == 'E' then
            table.insert(errors, located_line(item, 'error'))
        else
            table.insert(warnings, located_line(item, 'warning'))
        end
    end
    local others = {}
    for _, failure in ipairs(failures) do
        for _, other in ipairs(failure.others) do
            table.insert(others, ('%s  (%s)'):format(other, failure.target))
        end
    end

    add_section(lines, 'Errors', errors)
    add_section(lines, 'Warnings', warnings)
    add_section(lines, 'Without a file location', others)
    return lines
end

--- The report as a task, which replaces the report of the previous build and
--- opens in the output pane. It ends as failed, as the build did.
---@param failures qss.BuildFailure[]
function M.show(failures)
    if #failures == 0 then
        return
    end
    local task = require('overseer').new_task({
        name = REPORT,
        cmd = { REPORT },
        cwd = vim.fn.getcwd(),
        strategy = { 'qss_text', lines = M.render(failures), exit_code = 1 },
        components = {
            'on_exit_set_status',
            'unique',
            { 'open_output', on_start = 'always' },
        },
    })
    task:start()
end

return M
