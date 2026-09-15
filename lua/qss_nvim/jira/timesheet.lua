-- The week you logged, drawn rather than listed.
--
-- A list of worklogs answers "what did I write down". It does not answer the
-- questions actually asked of a timesheet: is a day short, which ticket took
-- the week, is anything missing before the sheet is submitted. Those are
-- comparisons, and comparisons are what a shape shows and a list does not.
local M = {}

local TITLE = 'Jira'
local NAME = 'jira://tempo'

local config = require('qss_nvim.jira.config')
local tempo = require('qss_nvim.jira.tempo')
local utils = require('qss_nvim.utils')

local DAY = 86400
local BAR = 34

local namespace = vim.api.nvim_create_namespace('qss.jira.timesheet')

-- Which Monday is on screen, as a timestamp. Kept here rather than in the
-- buffer, because moving a week redraws the same buffer.
local monday

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@return integer
local function this_monday()
    local now = os.time()
    local weekday = tonumber(os.date('%w', now)) or 0
    local midnight = os.time({
        year = tonumber(os.date('%Y', now)) or 1970,
        month = tonumber(os.date('%m', now)) or 1,
        day = tonumber(os.date('%d', now)) or 1,
        hour = 12,
    })
    return midnight - ((weekday + 6) % 7) * DAY
end

---@param at integer
---@return string
local function iso(at)
    return os.date('%Y-%m-%d', at) --[[@as string]]
end

--- A bar of `filled` out of `whole`, in BAR columns.
---@param filled number
---@param whole number
---@return string
local function bar(filled, whole)
    if whole <= 0 then
        return (' '):rep(BAR)
    end
    local width = math.min(BAR, math.floor(filled / whole * BAR + 0.5))
    return ('█'):rep(width) .. ('░'):rep(BAR - width)
end

---@class qss.jira.SheetLine
---@field worklog table? an entry, which can be deleted
---@field key string? an issue, which can be opened
---@field date string? a day, which can be logged against
---@field target integer? what that day asks for, zero on a holiday

-- How Tempo names a day that asks for nothing.
local NOT_WORKED = {
    NON_WORKING_DAY = 'weekend',
    HOLIDAY = 'holiday',
    HOLIDAY_AND_NON_WORKING_DAY = 'holiday',
}

---@param worklogs table[]
---@param keys table<string, string>
---@param schedule table<string, { required: integer, kind: string }>
---@return string[] lines, table<integer, qss.jira.SheetLine> owners
local function render(worklogs, keys, schedule)
    local fallback = config.options.daily_hours * 3600
    local lines = {}
    local owners = {}

    local by_day = {}
    local by_issue = {}
    local total = 0

    for _, worklog in ipairs(worklogs) do
        local seconds = worklog.timeSpentSeconds or 0
        total = total + seconds

        local day = worklog.startDate or ''
        by_day[day] = by_day[day] or { seconds = 0, entries = {} }
        by_day[day].seconds = by_day[day].seconds + seconds
        table.insert(by_day[day].entries, worklog)

        local id = worklog.issue and tostring(worklog.issue.id) or ''
        local key = keys[id] or id
        by_issue[key] = (by_issue[key] or 0) + seconds
    end

    local sunday = monday + 6 * DAY
    lines[#lines + 1] = ('# Timesheet  ·  %s to %s  ·  %s logged'):format(
        os.date('%d %b', monday), os.date('%d %b', sunday), tempo.to_duration(total))
    lines[#lines + 1] = '  i or <CR> acts on this line · < > move a week · . this week · r reload · q close'
    lines[#lines + 1] = ''

    -- The days, so a short one is visible without arithmetic. A holiday asks for
    -- nothing, and is said to be a holiday rather than left looking like a day
    -- somebody forgot to fill.
    local expected = 0
    for offset = 0, 6 do
        local at = monday + offset * DAY
        local date = iso(at)
        local held = by_day[date] and by_day[date].seconds or 0
        local day = schedule[date]
        local target = day and day.required or (offset < 5 and fallback or 0)
        local resting = NOT_WORKED[day and day.kind or ''] or (not day and offset >= 5 and 'weekend')
        expected = expected + target

        local note = ''
        if target == 0 then
            note = resting and ('  %s'):format(resting) or ''
        elseif held < target then
            note = ('  −%s'):format(tempo.to_duration(target - held))
        elseif held > target then
            note = ('  +%s'):format(tempo.to_duration(held - target))
        end

        lines[#lines + 1] = ('  %-11s %s  %8s%s'):format(
            os.date('%a %d %b', at), bar(held, target), tempo.to_duration(held), note)
        owners[#lines] = { date = date, target = target }
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('  %-11s %s  %8s  of %s'):format('week', bar(total, expected),
        tempo.to_duration(total), tempo.to_duration(expected))

    -- Where the week went.
    local ranked = {}
    for key, seconds in pairs(by_issue) do
        ranked[#ranked + 1] = { key = key, seconds = seconds }
    end
    table.sort(ranked, function(left, right)
        return left.seconds > right.seconds
    end)

    lines[#lines + 1] = ''
    lines[#lines + 1] = ('## By issue  (%d)'):format(#ranked)
    lines[#lines + 1] = ''
    local highest = ranked[1] and ranked[1].seconds or 0
    for _, entry in ipairs(ranked) do
        lines[#lines + 1] = ('  %-11s %s  %8s'):format(entry.key, bar(entry.seconds, highest),
            tempo.to_duration(entry.seconds))
        owners[#lines] = { key = entry.key }
    end
    if #ranked == 0 then
        lines[#lines + 1] = '  nothing logged this week'
    end

    -- Every entry, in the order it happened.
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('## Entries  (%d)'):format(#worklogs)
    lines[#lines + 1] = ''

    for offset = 0, 6 do
        local date = iso(monday + offset * DAY)
        local day = by_day[date]
        if day then
            table.sort(day.entries, function(left, right)
                return (left.startTime or '') < (right.startTime or '')
            end)
            for _, worklog in ipairs(day.entries) do
                local id = worklog.issue and tostring(worklog.issue.id) or ''
                lines[#lines + 1] = ('  %-10s %-6s %-8s %-11s %s'):format(
                    os.date('%a %d %b', monday + offset * DAY),
                    (worklog.startTime or ''):sub(1, 5),
                    tempo.to_duration(worklog.timeSpentSeconds or 0),
                    keys[id] or id, worklog.description or '')
                owners[#lines] = { worklog = worklog, key = keys[id] }
            end
        end
    end

    if #worklogs == 0 then
        lines[#lines + 1] = '  nothing yet'
    end

    return lines, owners
end

---@param buffer integer
---@param lines string[]
---@param owners table<integer, qss.jira.SheetLine>
local function paint(buffer, lines, owners)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

    for line, text in ipairs(lines) do
        local start = text:find('█')
        local stop = text:find('░') or (text:find('  ', start or 1) or 0)
        if start and owners[line] and owners[line].date then
            vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, start - 1, {
                end_col = math.max(start, (stop or start) - 1),
                hl_group = 'DiagnosticOk',
            })
        elseif start then
            vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, start - 1, {
                end_col = math.max(start, (stop or start) - 1),
                hl_group = 'DiagnosticInfo',
            })
        end
    end
end

---@return integer?
local function existing_buffer()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer):sub(-#NAME) == NAME then
            return buffer
        end
    end
    return nil
end

---@param buffer integer
local function bind_keys(buffer)
    local function act()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local owner = (vim.b[buffer].qss_jira_sheet or {})[tostring(line)] or {}

        if owner.worklog then
            local answer = vim.fn.confirm(
                ('Delete this worklog?\n%s'):format(vim.trim(vim.api.nvim_get_current_line())),
                '&Yes\n&No', 2)
            if answer ~= 1 then
                return
            end
            return tempo.remove(owner.worklog.tempoWorklogId, function()
                notify('worklog deleted', vim.log.levels.INFO)
                M.open()
            end)
        end

        if owner.key then
            return require('qss_nvim.jira.issue').open(owner.key)
        end

        if owner.date then
            return require('qss_nvim.jira.issue').find(function(key)
                tempo.log(key, { date = owner.date, on_done = M.open })
            end)
        end

        notify('nothing on this line', vim.log.levels.INFO)
    end

    vim.keymap.set('n', 'i', act, { buffer = buffer, desc = 'Act on what is under the cursor' })
    vim.keymap.set('n', '<CR>', act, { buffer = buffer, desc = 'Act on what is under the cursor' })

    vim.keymap.set('n', 'gd', function()
        local key = vim.api.nvim_get_current_line():match('%f[%w]%u[%u%d]*%-%d+')
        if not key then
            return notify('no issue on this line', vim.log.levels.WARN)
        end
        require('qss_nvim.jira.issue').open(key)
    end, { buffer = buffer, desc = 'Go to the issue on this line' })

    vim.keymap.set('n', '<', function()
        monday = monday - 7 * DAY
        M.open()
    end, { buffer = buffer, desc = 'The week before' })

    vim.keymap.set('n', '>', function()
        monday = monday + 7 * DAY
        M.open()
    end, { buffer = buffer, desc = 'The week after' })

    vim.keymap.set('n', '.', function()
        monday = this_monday()
        M.open()
    end, { buffer = buffer, desc = 'This week' })

    vim.keymap.set('n', 'r', function()
        M.open()
    end, { buffer = buffer, desc = 'Reload' })
end

--- Take over a buffer nvim has just made for jira://tempo.
---@param buffer integer
function M.adopt(buffer)
    -- A sheet opened fresh starts at this week. Without this the module would
    -- still hold whatever week was last browsed, so closing the sheet in
    -- November and reopening it would land back in November, with nothing on
    -- screen saying why.
    monday = this_monday()

    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'hide'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
    vim.b[buffer].qss_jira_view = 'tempo'
    vim.bo[buffer].filetype = 'jira'
    bind_keys(buffer)
    M.open({ focus = false })
end

--- Draw the week.
---@param options { focus: boolean? }? focus defaults to true
function M.open(options)
    monday = monday or this_monday()

    local buffer = existing_buffer()
    if not buffer then
        return vim.cmd.edit(vim.fn.fnameescape(NAME))
    end

    local from = iso(monday)
    local to = iso(monday + 6 * DAY)

    tempo.schedule(from, to, function(schedule)
    tempo.between(from, to, function(worklogs, keys)
        if not vim.api.nvim_buf_is_valid(buffer) then
            return
        end

        local lines, owners = render(worklogs, keys, schedule)
        local windows = vim.fn.win_findbuf(buffer)
        local cursors = {}
        for _, window in ipairs(windows) do
            cursors[window] = vim.api.nvim_win_get_cursor(window)
        end

        vim.bo[buffer].modifiable = true
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
        vim.bo[buffer].modifiable = false
        vim.bo[buffer].modified = false

        local keyed = {}
        for line, owner in pairs(owners) do
            keyed[tostring(line)] = owner
        end
        vim.b[buffer].qss_jira_sheet = keyed

        paint(buffer, lines, owners)

        for window, position in pairs(cursors) do
            if vim.api.nvim_win_is_valid(window) then
                vim.api.nvim_win_set_cursor(window, { math.min(position[1], #lines), position[2] })
            end
        end

        if options and options.focus == false then
            return
        end

        local window = utils.main_window()
        if window and vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_set_current_win(window)
        end
        if vim.api.nvim_get_current_buf() ~= buffer then
            vim.cmd.buffer(buffer)
        end
    end)
    end)
end

--- Redraw only when a sheet is already on screen.
function M.refresh()
    if existing_buffer() then
        M.open({ focus = false })
    end
end

return M
