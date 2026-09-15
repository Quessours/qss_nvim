-- The sprint report and the burndown, drawn in the buffer.
--
-- Both come from the greenhopper endpoints the Jira board itself calls. They are
-- not part of the documented REST API, so they can change without notice; the
-- code checks the shape of what comes back rather than trusting it.
--
-- The burndown is rebuilt rather than read: the endpoint reports changes, not a
-- curve. Each change says an issue entered the sprint, left it, crossed into a
-- done column, or had its estimate moved. Replaying them in order gives the
-- remaining work at every moment, which is the line.
local M = {}

local TITLE = 'Jira'
-- The running sprint keeps the plain name, because that is the one worth
-- typing and it stays meaningful as sprints come and go. Any other sprint is
-- named by its id, so that the id survives the trip through `:edit` instead of
-- being lost and resolved back to the active one.
local NAME = 'jira://sprint'

---@param sprint_id integer?
---@return string
local function name_of(sprint_id)
    if not sprint_id then
        return NAME
    end
    return ('%s/%d'):format(NAME, sprint_id)
end

local config = require('qss_nvim.jira.config')
local http = require('qss_nvim.jira.http')
local utils = require('qss_nvim.utils')

local DAY = 86400000

-- Two spaces of indent, an eight-wide value label and the axis line: the bars
-- begin one column after this, and the dates line up under that same column.
local GUTTER = 11
local MIN_WIDTH, MAX_WIDTH = 24, 220
local MIN_HEIGHT, MAX_HEIGHT = 8, 40

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param seconds number
---@return string
local function duration(seconds)
    if seconds == 0 then
        return '0'
    end
    local hours = seconds / 3600
    if hours < 8 then
        return ('%.1fh'):format(hours)
    end
    return ('%.1fd'):format(hours / 8)
end

---@class qss.jira.Point
---@field at integer milliseconds
---@field remaining number

--- The remaining work at every moment the sprint changed.
---@param chart table what the burndown endpoint returned
---@return qss.jira.Point[] points, string unit
local function replay(chart)
    local stamps = {}
    for stamp in pairs(chart.changes or {}) do
        stamps[#stamps + 1] = stamp
    end
    table.sort(stamps, function(left, right)
        return tonumber(left) < tonumber(right)
    end)

    local estimate = {}
    local inside = {}
    local done = {}
    local points = {}

    for _, stamp in ipairs(stamps) do
        for _, change in ipairs(chart.changes[stamp]) do
            local key = change.key
            if change.added ~= nil then
                inside[key] = change.added
            end
            if change.timeC then
                estimate[key] = change.timeC.newEstimate or 0
            end
            if change.column then
                done[key] = not change.column.notDone
            end
        end

        local remaining = 0
        for key, held in pairs(estimate) do
            if inside[key] and not done[key] then
                remaining = remaining + held
            end
        end
        points[#points + 1] = { at = tonumber(stamp), remaining = remaining }
    end

    local field = chart.statisticField or {}
    return points, field.renderer == 'duration' and 'time' or 'points'
end

--- The value of the line at one moment: the last change at or before it.
---@param points qss.jira.Point[]
---@param at integer
---@return number
local function value_at(points, at)
    local held = 0
    for _, point in ipairs(points) do
        if point.at > at then
            break
        end
        held = point.remaining
    end
    return held
end

--- The working fraction of the sprint elapsed by a moment, so the guide line
--- falls on working days only and stays flat across a weekend.
---@param rates table[]
---@param at integer
---@return number
local function worked_by(rates, at)
    local total = 0
    local before = 0
    for _, rate in ipairs(rates or {}) do
        local span = (rate.end_ or rate['end']) - rate.start
        local worked = span * (rate.rate or 0)
        total = total + worked
        if at >= (rate.end_ or rate['end']) then
            before = before + worked
        elseif at > rate.start then
            before = before + (at - rate.start) * (rate.rate or 0)
        end
    end
    if total == 0 then
        return 0
    end
    return before / total
end

--- How much room the chart has. The window the report will land in when there
--- is one, the whole editor otherwise, because the size is decided before the
--- buffer is placed.
---@return integer columns, integer rows
local function viewport()
    local window = utils.main_window()
    local width = window and vim.api.nvim_win_get_width(window) or vim.o.columns
    local height = window and vim.api.nvim_win_get_height(window) or vim.o.lines

    local columns = math.max(MIN_WIDTH, math.min(MAX_WIDTH, width - GUTTER - 1))
    -- Around half the height, so the totals above and the issue lists below stay
    -- reachable with one scroll rather than being pushed off the screen.
    local rows = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(height * 0.55)))
    return columns, rows
end

--- The dates under the axis, spaced so that the labels never touch.
---@param start_at integer
---@param end_at integer
---@param columns integer
---@return string
local function axis_dates(start_at, end_at, columns)
    local span = end_at - start_at
    local days = math.max(1, math.ceil(span / DAY))
    -- A label is six characters wide, so leave at least eight between them.
    local every = math.max(1, math.ceil(days / math.max(1, math.floor(columns / 8))))

    local marks = {}
    for day = 0, days, every do
        local at = start_at + day * DAY
        local column = math.floor((at - start_at) / span * (columns - 1)) + 1
        marks[#marks + 1] = { column = column, text = os.date('%d %b', math.floor(at / 1000)) }
    end

    local line = {}
    local width = 0
    for _, mark in ipairs(marks) do
        -- A label that would run past the axis is left out rather than allowed
        -- to push the line wider than the chart and start a sideways scroll.
        if mark.column - 1 >= width and mark.column - 1 + #mark.text <= columns then
            line[#line + 1] = (' '):rep(mark.column - 1 - width)
            line[#line + 1] = mark.text
            width = mark.column - 1 + #mark.text
        end
    end
    return (' '):rep(GUTTER) .. table.concat(line)
end

---@param chart table
---@param points qss.jira.Point[]
---@param unit string
---@return string[]
local function plot(chart, points, unit)
    local start_at = chart.startTime
    local end_at = chart.endTime
    local now = chart.now or os.time() * 1000
    local rates = (chart.workRateData or {}).rates

    -- One column per day would leave most of a wide window empty and hide every
    -- change made inside a day. The axis is sampled at whatever resolution the
    -- window affords instead.
    local columns, height = viewport()

    local actual = {}
    local guide = {}
    local highest = 0

    local opening = value_at(points, start_at)
    for column = 1, columns do
        local at = start_at + math.floor((column - 1) * (end_at - start_at) / math.max(1, columns - 1))
        local held = at <= now and value_at(points, at) or nil
        actual[column] = held
        guide[column] = opening * (1 - worked_by(rates, at))
        highest = math.max(highest, held or 0, guide[column])
    end

    if highest == 0 then
        return { '  nothing is estimated in this sprint, so there is no line to draw' }
    end

    -- A label every few rows, often enough to read the scale and rarely enough
    -- to leave the axis clean.
    local label_every = height >= 24 and 3 or 4

    local lines = {}
    for row = height, 1, -1 do
        local ceiling = highest * row / height
        local floor = highest * (row - 1) / height
        local drawn = {}

        for column = 1, columns do
            local held = actual[column]
            local on_actual = held ~= nil and held > floor and held <= ceiling
            local on_guide = guide[column] > floor and guide[column] <= ceiling
            drawn[#drawn + 1] = on_actual and '█' or (on_guide and '·' or ' ')
        end

        local label = (row % label_every == 0 or row == height)
            and (unit == 'time' and duration(ceiling) or ('%.0f'):format(ceiling))
            or ''
        lines[#lines + 1] = ('  %8s │%s'):format(label, table.concat(drawn))
    end

    lines[#lines + 1] = ('  %8s └%s'):format('0', ('─'):rep(columns))
    lines[#lines + 1] = axis_dates(start_at, end_at, columns)
    lines[#lines + 1] = ''
    local today = os.date('%d %b', math.floor(now / 1000))
    local legend = columns >= 76
        and ('  █ remaining work    · guide line, flat on non-working days    today %s'):format(today)
        or ('  █ remaining   · guide    today %s'):format(today)
    lines[#lines + 1] = legend
    return lines
end

---@param report table
---@param chart table
---@param points qss.jira.Point[]
---@param unit string
---@return string[]
local function compose(report, chart, points, unit)
    local sprint = report.sprint or {}
    local contents = report.contents or {}

    ---@param bucket table[]?
    ---@param heading string
    ---@param lines string[]
    local function section(bucket, heading, lines)
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('## %s  (%d)'):format(heading, #(bucket or {}))
        lines[#lines + 1] = ''
        for _, issue in ipairs(bucket or {}) do
            -- `assignee` in this answer is an account id; the readable name is
            -- assigneeName, which is absent when nobody is assigned.
            local who = issue.assigneeName or 'unassigned'
            lines[#lines + 1] = ('  %-11s %-16s %-22s %s'):format(issue.key,
                (issue.statusName or ''):sub(1, 16), who:sub(1, 22), issue.summary or '')
        end
        if #(bucket or {}) == 0 then
            lines[#lines + 1] = '  none'
        end
    end

    local lines = {
        ('# %s  ·  sprint report'):format(sprint.name or '?'),
        '  i or <CR> acts on the issue under the cursor   r reload   q close',
        '',
    }

    local everything = (contents.allIssuesEstimateSum or {}).value or 0
    local left = (contents.issuesNotCompletedEstimateSum or {}).value or 0
    local finished = everything - left

    lines[#lines + 1] = ('  Estimated   %s'):format(unit == 'time' and duration(everything) or everything)
    lines[#lines + 1] = ('  Completed   %s'):format(unit == 'time' and duration(finished) or finished)
    lines[#lines + 1] = ('  Remaining   %s'):format(unit == 'time' and duration(left) or left)
    lines[#lines + 1] = ('  Added mid-sprint  %d issues'):format(#(contents.issueKeysAddedDuringSprint and
        vim.tbl_keys(contents.issueKeysAddedDuringSprint) or {}))

    local goal = vim.trim(sprint.goal or '')
    if goal ~= '' then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '## Goal'
        lines[#lines + 1] = ''
        for _, line in ipairs(vim.split(goal, '\n', { plain = true })) do
            lines[#lines + 1] = '  ' .. line
        end
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '## Burndown'
    lines[#lines + 1] = ''
    vim.list_extend(lines, plot(chart, points, unit))

    section(contents.completedIssues, 'Completed', lines)
    section(contents.issuesNotCompletedInCurrentSprint, 'Not completed', lines)
    section(contents.puntedIssues, 'Removed from the sprint', lines)
    section(contents.issuesCompletedInAnotherSprint, 'Completed in another sprint', lines)

    return lines
end

---@param name string
---@return integer?
local function existing_buffer(name)
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer):sub(-#name) == name then
            return buffer
        end
    end
    return nil
end

---@param buffer integer
---@param sprint_id integer?
local function bind_keys(buffer, sprint_id)
    local function act()
        local line = vim.api.nvim_get_current_line()
        local key = not line:match('^#') and line:match('%f[%w]%u[%u%d]*%-%d+') or nil
        if not key then
            return notify('no issue on this line', vim.log.levels.WARN)
        end
        require('qss_nvim.jira.actions').menu(key)
    end

    vim.keymap.set('n', '<CR>', act, { buffer = buffer, desc = 'Act on the issue under the cursor' })
    vim.keymap.set('n', 'i', act, { buffer = buffer, desc = 'Act on the issue under the cursor' })

    local function follow()
        local line = vim.api.nvim_get_current_line()
        local key = not line:match('^#') and line:match('%f[%w]%u[%u%d]*%-%d+') or nil
        if not key then
            return notify('no issue on this line', vim.log.levels.WARN)
        end
        require('qss_nvim.jira.issue').open(key)
    end

    vim.keymap.set('n', 'gd', follow, { buffer = buffer, desc = 'Go to the issue under the cursor' })
    vim.keymap.set('n', '<C-]>', follow, { buffer = buffer, desc = 'Go to the issue under the cursor' })

    vim.keymap.set('n', 'r', function()
        M.open(sprint_id)
    end, { buffer = buffer, desc = 'Reload the report' })

end

---@param lines string[]
---@param name string
local function show(lines, name)
    local buffer = existing_buffer(name)
    if not buffer then
        return
    end

    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].modified = false

    local window = utils.main_window()
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_set_current_win(window)
    end
    if vim.api.nvim_get_current_buf() ~= buffer then
        vim.cmd.buffer(buffer)
    end
end

--- Take over a buffer nvim has just made for jira://sprint or jira://sprint/ID.
---@param buffer integer
---@param sprint_id integer?
function M.adopt(buffer, sprint_id)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'hide'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
    vim.b[buffer].qss_jira_view = 'sprint'
    vim.b[buffer].qss_jira_sprint = sprint_id
    vim.bo[buffer].filetype = 'jira'
    bind_keys(buffer, sprint_id)
    M.open(sprint_id)
end

--- The report and the burndown of one sprint, or of the running one.
---@param sprint_id integer?
function M.open(sprint_id)
    local instance = config.instance()
    if not (instance and instance.board_id) then
        return notify('the board id is missing from the jira-cli config. Re-run jira init.',
            vim.log.levels.ERROR)
    end
    local board_id = instance.board_id

    local name = name_of(sprint_id)

    -- Claimed before anything is fetched, so the report is built once rather
    -- than built, thrown away by the redirect, and built again.
    if not existing_buffer(name) then
        return vim.cmd.edit(vim.fn.fnameescape(name))
    end

    local function draw(id)
        local report
        local chart

        local function ready()
            if not (report and chart) then
                return
            end
            local points, unit = replay(chart)
            show(compose(report, chart, points, unit), name)
        end

        http.jira_rest(('/rest/greenhopper/1.0/rapid/charts/sprintreport?rapidViewId=%s&sprintId=%d')
            :format(board_id, id), function(decoded)
            report = decoded
            ready()
        end)

        http.jira_rest(('/rest/greenhopper/1.0/rapid/charts/scopechangeburndownchart?rapidViewId=%s&sprintId=%d')
            :format(board_id, id), function(decoded)
            chart = decoded
            ready()
        end)
    end

    if sprint_id then
        return draw(sprint_id)
    end

    http.jira_rest(('/rest/agile/1.0/board/%s/sprint?state=active'):format(board_id), function(decoded)
        local sprints = decoded.values or {}
        if #sprints == 0 then
            return notify('no sprint is running on this board', vim.log.levels.WARN)
        end
        draw(sprints[1].id)
    end)
end

--- Every sprint of the board. The endpoint answers 50 at a time and oldest
--- first, so asking once returns the sprints nobody wants a report on and hides
--- every recent one.
---@param board_id string
---@param callback fun(sprints: table[])
local function all_sprints(board_id, callback)
    local sprints = {}

    local function page(start_at)
        local path = ('/rest/agile/1.0/board/%s/sprint?state=active,closed&startAt=%d&maxResults=50')
            :format(board_id, start_at)

        http.jira_rest(path, function(decoded)
            local batch = decoded.values or {}
            vim.list_extend(sprints, batch)

            if decoded.isLast == false and #batch > 0 then
                return page(start_at + #batch)
            end
            callback(sprints)
        end)
    end

    page(0)
end

--- Choose which sprint to report on, closed ones included.
function M.pick()
    local instance = config.instance()
    if not (instance and instance.board_id) then
        return notify('the board id is missing from the jira-cli config', vim.log.levels.ERROR)
    end

    all_sprints(instance.board_id, function(sprints)
        if #sprints == 0 then
            return notify('this board has no sprint', vim.log.levels.WARN)
        end

        -- The board answers oldest first, and the sprint worth a report is
        -- almost always the last one, so the list is turned around.
        local items = {}
        for index = #sprints, 1, -1 do
            local sprint = sprints[index]
            items[#items + 1] = {
                text = ('%-18s %-7s %s'):format(sprint.name, (sprint.state or ''):lower(),
                    (sprint.startDate or ''):sub(1, 10)),
                -- The running sprint opens under the plain name, so picking it
                -- lands in the same buffer that <leader>jcs and :JiraSprint use
                -- rather than a second copy of the same report.
                sprint_id = (sprint.state or ''):lower() ~= 'active' and sprint.id or nil,
                idx = #items + 1,
            }
        end

        Snacks.picker({
            source = 'jira_sprint_reports',
            items = items,
            format = 'text',
            title = 'Sprint report',
            layout = { preset = 'select' },
            confirm = function(picker, item)
                picker:close()
                if item then
                    M.open(item.sprint_id)
                end
            end,
        })
    end)
end

return M
