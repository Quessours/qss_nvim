-- The sprint as the board draws it, rather than as a flat list.
--
-- The columns and their order come from the board itself, and a column is a set
-- of status ids rather than of status names: this board puts eight statuses in
-- "To Do" alone, so grouping by name would draw eight columns that the board
-- does not have. `issue list --raw` reports a status name and no id, so the
-- issues come from the agile API, which reports both.
local M = {}

local TITLE = 'Jira'
local BOARD = 'jira://board'
local BACKLOG = 'jira://backlog'

local cache = require('qss_nvim.jira.cache')
local config = require('qss_nvim.jira.config')
local http = require('qss_nvim.jira.http')
local utils = require('qss_nvim.utils')

local namespace = vim.api.nvim_create_namespace('qss.jira.board')
local clock_namespace = vim.api.nvim_create_namespace('qss.jira.standup')

local LIST_LEGEND = '  i or <CR> acts   e, v or gd open   t transition   o browser   y yank   r reload   q close'
local BOARD_LEGEND = '  i or <CR> acts   e, v or gd open   t transition   o browser   y yank   s standup   r reload   q close'
local READY_LEGEND = '  > start   c countdown   T time per person   x absent or back   S shuffle   s cancel   i or <CR> acts   e, v or gd open   t transition   r reload'
local STANDUP_LEGEND ='  < > previous or next person   T time per person   x absent or back   S shuffle   s end the standup   i or <CR> acts   e, v or gd open   t transition   r reload'

---@class qss.jira.Person
---@field id string? the account id, absent for the unassigned issues
---@field name string
---@field absent boolean? skipped by < and >, but kept in its place in the list

---@class qss.jira.Standup
---@field people qss.jira.Person[]
---@field index integer the person speaking, 0 until the standup starts
---@field since integer? when the standup started, in seconds
---@field person_since integer? when the person speaking began, in seconds
---@field start_at integer? when the countdown before the start runs out, in seconds
---@field announced boolean? the end of the countdown was announced
---@field person_announced boolean? the person speaking was told they are out of time
---@field timer uv.uv_timer_t? the clock, running during the countdown and the standup

---@type qss.jira.Standup?
local standup

-- Set when a standup is asked for before the board has anything to walk
-- through, so it begins as soon as the board is drawn.
local standup_pending = false

--- What the board last fetched, so that moving to the next person redraws at
--- once rather than asking Jira again. `r` still fetches.
---@type { columns: qss.jira.Column[], issues: table[], account_id: string?, sprint: { name: string } }?
local latest

-- A day, because a board gains a column about as often as a project is created.
local COLUMNS_TTL = 86400

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param callback fun(board_id: string)
local function with_board(callback)
    local instance = config.instance()
    if not (instance and instance.board_id) then
        return notify('the board id is missing from the jira-cli config. Re-run jira init.',
            vim.log.levels.ERROR)
    end
    callback(instance.board_id)
end

---@class qss.jira.Column
---@field name string
---@field statuses table<string, boolean> status ids that land in this column

---@param board_id string
---@param callback fun(columns: qss.jira.Column[])
local function columns_of(board_id, callback)
    local cache_key = ('board.columns.%s'):format(board_id)
    local remembered = cache.get(cache_key)
    if remembered then
        return callback(remembered)
    end

    http.jira_rest(('/rest/agile/1.0/board/%s/configuration'):format(board_id), function(decoded)
        local columns = {}
        for _, column in ipairs(decoded.columnConfig and decoded.columnConfig.columns or {}) do
            local statuses = {}
            for _, status in ipairs(column.statuses or {}) do
                statuses[tostring(status.id)] = true
            end
            columns[#columns + 1] = { name = column.name, statuses = statuses }
        end

        if #columns == 0 then
            return notify('the board reports no column', vim.log.levels.ERROR)
        end
        cache.set(cache_key, columns, COLUMNS_TTL)
        callback(columns)
    end)
end

--- Your account id, so your own rows can be marked. It never changes, so the
--- lookup happens once for the life of the cache.
---@param callback fun(account_id: string?)
local function with_account(callback)
    local remembered = cache.get('tempo.account_id')
    if remembered then
        return callback(remembered)
    end
    http.jira_rest('/rest/api/3/myself', function(me)
        cache.set('tempo.account_id', me.accountId)
        callback(me.accountId)
    end)
end

---@param board_id string
---@param callback fun(sprint: { id: integer, name: string })
local function active_sprint(board_id, callback)
    http.jira_rest(('/rest/agile/1.0/board/%s/sprint?state=active'):format(board_id), function(decoded)
        local sprints = decoded.values or {}
        if #sprints == 0 then
            return notify('no sprint is running on this board', vim.log.levels.WARN)
        end
        callback(sprints[1])
    end)
end

---@param board_id string
---@param sprint_id integer
---@param callback fun(issues: table[])
local function sprint_issues(board_id, sprint_id, callback)
    local path = ('/rest/agile/1.0/board/%s/sprint/%d/issue?maxResults=200&fields=summary,status,assignee,issuetype,priority,timetracking')
        :format(board_id, sprint_id)

    http.jira_rest(path, function(decoded)
        callback(decoded.issues or {})
    end)
end

---@param issue table
---@return table? assignee
local function assignee_of(issue)
    local assignee = issue.fields.assignee
    return type(assignee) == 'table' and assignee or nil
end

---@class qss.jira.BoardRow
---@field text string
---@field key string? absent on a heading or a blank line
---@field mine boolean
---@field key_col integer? byte offset of the key
---@field dim_to integer? byte offset where the summary starts
---@field person integer? the index of the person on a line of the standup list
---@field hl string? a highlight for the whole line
---@field time_col integer? byte offset of the estimates
---@field time_len integer? byte length of the estimates
---@field time_hl string? a highlight for the estimates

--- `<remaining> / <original>`, as Jira writes them (`1d 2h`), with `-` for an
--- estimate nobody set. The dash is one byte, so the column pads evenly.
---@param issue table
---@return string text
---@return string? hl red with nothing left, orange with less than a day left of a task of a day or more
local function time_of(issue)
    local tracking = issue.fields.timetracking
    if type(tracking) ~= 'table' then
        tracking = {}
    end
    local text = ('%s / %s'):format(tracking.remainingEstimate or '-', tracking.originalEstimate or '-')

    local remaining = tracking.remainingEstimateSeconds or 0
    local original = tracking.originalEstimateSeconds or 0
    local day = config.day_seconds()
    if remaining == 0 then
        return text, 'QssJiraEstimateNone'
    end
    if original >= day and remaining < day then
        return text, 'QssJiraEstimateLow'
    end
    return text, nil
end

---@param columns qss.jira.Column[]
---@param issues table[]
---@param account_id string?
---@return qss.jira.BoardRow[]
local function rows_of(columns, issues, account_id)
    local by_column = {}
    for index in ipairs(columns) do
        by_column[index] = {}
    end
    local elsewhere = {}

    for _, issue in ipairs(issues) do
        local status_id = tostring(issue.fields.status.id)
        local placed = false
        for index, column in ipairs(columns) do
            if column.statuses[status_id] then
                local bucket = by_column[index]
                bucket[#bucket + 1] = issue
                placed = true
                break
            end
        end
        if not placed then
            elsewhere[#elsewhere + 1] = issue
        end
    end

    local rows = {}

    ---@param name string
    ---@param bucket table[]
    local function render_column(name, bucket)
        rows[#rows + 1] = { text = ('## %s  (%d)'):format(name, #bucket), mine = false }
        rows[#rows + 1] = { text = '', mine = false }

        for _, issue in ipairs(bucket) do
            local fields = issue.fields
            local assigned = assignee_of(issue)
            local assignee = assigned and assigned.displayName or 'unassigned'
            local mine = account_id ~= nil and assigned ~= nil and assigned.accountId == account_id

            -- The offsets are taken here rather than guessed back out of the
            -- line: a marker or an accent is more than one byte wide, and an
            -- extmark counts bytes.
            local marker = mine and '▌' or ' '
            local prefix = ('%s %-11s'):format(marker, issue.key)
            local middle = ('%-14s %-20s '):format(fields.issuetype.name:sub(1, 14), assignee:sub(1, 20))
            local time, time_hl = time_of(issue)
            local time_col = #prefix + 1 + #middle
            middle = ('%s%-17s '):format(middle, time)

            rows[#rows + 1] = {
                text = ('%s %s%s'):format(prefix, middle, fields.summary),
                key = issue.key,
                mine = mine,
                key_col = #marker + 1,
                dim_to = #prefix + 1 + #middle,
                time_col = time_col,
                time_len = #time,
                time_hl = time_hl,
            }
        end
        rows[#rows + 1] = { text = '', mine = false }
    end

    for index, column in ipairs(columns) do
        render_column(column.name, by_column[index])
    end
    if #elsewhere > 0 then
        render_column('Not on the board', elsewhere)
    end

    return rows
end

---@param buffer integer
---@param rows qss.jira.BoardRow[]
---@param offset integer lines drawn above the first row
local function paint(buffer, rows, offset)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    -- Bright enough to read on a black background.
    vim.api.nvim_set_hl(0, 'QssJiraEstimateLow', { fg = '#ff9933', default = true })
    vim.api.nvim_set_hl(0, 'QssJiraEstimateNone', { fg = '#ff5f5f', default = true })

    for index, row in ipairs(rows) do
        if row.hl then
            vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1 + offset, 0, {
                end_col = #row.text,
                hl_group = row.hl,
            })
        end
        if row.key then
            local line = index - 1 + offset
            vim.api.nvim_buf_set_extmark(buffer, namespace, line, row.key_col, {
                end_col = row.key_col + #row.key,
                hl_group = row.mine and 'DiagnosticOk' or 'Identifier',
            })
            local dim_to = math.min(row.dim_to, #row.text)
            if not row.time_hl then
                vim.api.nvim_buf_set_extmark(buffer, namespace, line, row.key_col + #row.key, {
                    end_col = dim_to,
                    hl_group = 'Comment',
                })
            else
                -- The dimming goes around a colored estimate rather than under it.
                local time_end = row.time_col + row.time_len
                vim.api.nvim_buf_set_extmark(buffer, namespace, line, row.key_col + #row.key, {
                    end_col = row.time_col,
                    hl_group = 'Comment',
                })
                vim.api.nvim_buf_set_extmark(buffer, namespace, line, row.time_col, {
                    end_col = time_end,
                    hl_group = row.time_hl,
                })
                vim.api.nvim_buf_set_extmark(buffer, namespace, line, time_end, {
                    end_col = dim_to,
                    hl_group = 'Comment',
                })
            end
        end
    end
end

--- The issue on the current line. A heading is skipped on purpose: a sprint
--- called LIS-41 reads exactly like an issue key, and the title line is the one
--- the cursor sits on when the view opens.
---@return string?
local function key_under_cursor()
    local line = vim.api.nvim_get_current_line()
    if line:match('^#') then
        return nil
    end
    return line:match('%f[%w]%u[%u%d]*%-%d+')
end

---@param buffer integer
---@param reload fun()
local function bind_keys(buffer, reload)
    ---@param lhs string
    ---@param description string
    ---@param run fun(key: string)
    local function on_issue(lhs, description, run)
        vim.keymap.set('n', lhs, function()
            local key = key_under_cursor()
            if not key then
                return notify('no issue on this line', vim.log.levels.WARN)
            end
            run(key)
        end, { buffer = buffer, desc = description })
    end

    -- i and <CR> are the same gesture here as in a ticket buffer: act on the
     -- line under the cursor.
    local function menu(key)
        require('qss_nvim.jira.actions').menu(key)
    end
    on_issue('<CR>', 'Act on the issue under the cursor', menu)
    on_issue('i', 'Act on the issue under the cursor', menu)
    -- e and v both open the ticket: v for "view", e for "edit", and the buffer
    -- they open is the same one, because reading and editing happen in it.
    local function open_issue(key)
        require('qss_nvim.jira.issue').open(key)
    end
    on_issue('v', 'Open the issue', open_issue)
    on_issue('e', 'Open the issue to edit it', open_issue)
    on_issue('gd', 'Go to the issue under the cursor', open_issue)
    on_issue('<C-]>', 'Go to the issue under the cursor', open_issue)
    on_issue('o', 'Open the issue in the browser', function(key)
        require('qss_nvim.jira.actions').open_in_browser(key)
    end)
    on_issue('y', 'Yank the issue key', function(key)
        require('qss_nvim.jira.actions').yank_key(key)
    end)
    on_issue('t', 'Transition the issue', function(key)
        require('qss_nvim.jira.picker').transition(key, M.open)
    end)

    vim.keymap.set('n', 'r', reload, { buffer = buffer, desc = 'Reload' })

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

---@class qss.jira.ListView
---@field name string the buffer name
---@field title string
---@field rows qss.jira.BoardRow[]
---@field legend string? the key legend, LIST_LEGEND when absent
---@field focus boolean
---@field reload fun()

---@param view qss.jira.ListView
local function show(view)
    local buffer = existing_buffer(view.name)
    if not buffer then
        return
    end

    local rows = view.rows
    -- A list view, so single letters are the convention here, unlike the prose
    -- buffer of one issue. The legend keeps them from being a guess.
    local lines = {
        ('# %s'):format(view.title),
        view.legend or LIST_LEGEND,
        '',
    }
    local offset = #lines
    for _, row in ipairs(rows) do
        lines[#lines + 1] = row.text
    end

    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].modified = false

    paint(buffer, rows, offset)

    local windows = vim.fn.win_findbuf(buffer)
    for _, window in ipairs(windows) do
        local position = vim.api.nvim_win_get_cursor(window)
        vim.api.nvim_win_set_cursor(window, { math.min(position[1], #lines), position[2] })
    end

    if not view.focus then
        return
    end

    local window = utils.main_window()
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_set_current_win(window)
    end
    if vim.api.nvim_get_current_buf() ~= buffer then
        vim.cmd.buffer(buffer)
    end
end

--- Take over a buffer nvim has just made for jira://board or jira://backlog.
---@param buffer integer
---@param which string
function M.adopt(buffer, which)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'hide'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
    vim.b[buffer].qss_jira_view = which
    vim.bo[buffer].filetype = 'jira'

    bind_keys(buffer, function()
        if which == 'backlog' then
            return M.backlog()
        end
        cache.invalidate_prefix('board.')
        M.open()
    end)

    if which == 'backlog' then
        return M.backlog({ focus = false })
    end

    -- s on the backlog would walk nobody: a backlog has no sprint to report on.
    vim.keymap.set('n', 's', M.standup, { buffer = buffer, desc = 'Start or end the standup' })
    vim.keymap.set('n', '>', function() M.step(1) end, { buffer = buffer, desc = 'Next person' })
    vim.keymap.set('n', '<', function() M.step(-1) end, { buffer = buffer, desc = 'Previous person' })
    vim.keymap.set('n', 'S', M.shuffle, { buffer = buffer, desc = 'Shuffle the people left' })
    vim.keymap.set('n', 'x', M.toggle_absent, { buffer = buffer, desc = 'Mark absent or back' })
    vim.keymap.set('n', 'c', M.countdown, { buffer = buffer, desc = 'Countdown before the start' })
    vim.keymap.set('n', 'T', M.person_time, { buffer = buffer, desc = 'Time per person' })
    vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buffer,
        once = true,
        desc = 'Stop the standup clock with the board',
        callback = function()
            if standup and standup.timer then
                standup.timer:close()
            end
            standup = nil
            require('qss_nvim.jira.stop_sign').hide()
        end,
    })

    M.open({ focus = false })
end

---@param seconds integer
---@return string
local function clock(seconds)
    return ('%02d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

-- The time per person last asked for with `T`, kept for the next standups of
-- the session.
---@type integer?
local person_time

---@return integer seconds 0 for no limit
local function person_limit()
    return person_time or config.options.standup_person_time or 0
end

--- The countdown before the start, then the time of the person speaking and of
--- the whole standup, at the end of the title line. Virtual text, so the clock
--- ticks without rewriting the buffer under the cursor every second.
local function paint_clock()
    local buffer = existing_buffer(BOARD)
    if not buffer then
        return
    end
    vim.api.nvim_buf_clear_namespace(buffer, clock_namespace, 0, -1)
    if not standup then
        return
    end

    local now = os.time()
    local text, hl
    if standup.since and standup.person_since then
        local spoken = now - standup.person_since
        local limit = person_limit()
        local total = clock(now - standup.since)
        if limit == 0 then
            text, hl = ('   %s   total %s'):format(clock(spoken), total), 'DiagnosticInfo'
        elseif spoken < limit then
            text, hl = ('   %s / %s   total %s'):format(clock(spoken), clock(limit), total), 'DiagnosticInfo'
        else
            text = ('   %s / %s, out of time   total %s'):format(clock(spoken), clock(limit), total)
            hl = 'DiagnosticError'
            if not standup.person_announced then
                standup.person_announced = true
                notify(('%s is out of time. > gives the word to the next person, <Esc> hushes the sign.')
                    :format(standup.people[standup.index].name), vim.log.levels.WARN)
                require('qss_nvim.jira.stop_sign').show()
            end
        end
    elseif standup.start_at and now < standup.start_at then
        text, hl = ('   starts in %s'):format(clock(standup.start_at - now)), 'DiagnosticInfo'
    elseif standup.start_at then
        text, hl = ('   time to start, %s late'):format(clock(now - standup.start_at)), 'DiagnosticWarn'
        if not standup.announced then
            standup.announced = true
            notify('time to start the standup. > gives the word to the first person, <Esc> hushes the sign.',
                vim.log.levels.WARN)
            require('qss_nvim.jira.stop_sign').show()
        end
    else
        return
    end

    vim.api.nvim_buf_set_extmark(buffer, clock_namespace, 0, 0, {
        virt_text = { { text, hl } },
        virt_text_pos = 'eol',
    })
end

---@return uv.uv_timer_t
local function start_clock()
    local timer = assert(vim.uv.new_timer())
    timer:start(1000, 1000, vim.schedule_wrap(paint_clock))
    return timer
end

--- The standup order, one line per person, so that who spoke, who speaks and
--- who is next stay on screen, and `x` has a line to act on.
---@param current qss.jira.Standup
---@return qss.jira.BoardRow[]
local function people_rows(current)
    local present = 0
    for _, person in ipairs(current.people) do
        present = present + (person.absent and 0 or 1)
    end

    local rows = {
        { text = ('## People  (%d present of %d)'):format(present, #current.people), mine = false },
        { text = '', mine = false },
    }
    for index, person in ipairs(current.people) do
        local marker, hl = '·', nil
        if person.absent then
            marker, hl = '✗', 'DiagnosticWarn'
        elseif index == current.index then
            marker, hl = '▶', 'DiagnosticOk'
        elseif index < current.index then
            marker, hl = '✓', 'Comment'
        end
        rows[#rows + 1] = {
            text = ('  %s %s%s'):format(marker, person.name, person.absent and '  (absent)' or ''),
            mine = false,
            person = index,
            hl = hl,
        }
    end
    rows[#rows + 1] = { text = '', mine = false }
    return rows
end

-- Filled by draw: which person each line of the standup list shows, and the
-- line of the first issue, both 1-based.
---@type table<integer, integer>
local person_at = {}
local first_issue_line = 1

--- Draw what the board last fetched, narrowed to one person during a standup.
---@param focus boolean
local function draw(focus)
    if not latest then
        return
    end

    local issues = latest.issues
    local title = ('%s  (%d issues)'):format(latest.sprint.name, #issues)
    local legend = BOARD_LEGEND
    local rows = {}
    local person = standup and standup.people[standup.index]
    if person then
        issues = vim.tbl_filter(function(issue)
            local assigned = assignee_of(issue)
            return (assigned and assigned.accountId) == person.id
        end, issues)
        title = ('Standup · %s  (%d issues)'):format(person.name, #issues)
        legend = STANDUP_LEGEND
    elseif standup then
        title = ('Standup, not started · %s  (%d issues)'):format(latest.sprint.name, #issues)
        legend = READY_LEGEND
    end
    if standup then
        rows = people_rows(standup)
    end
    vim.list_extend(rows, rows_of(latest.columns, issues, latest.account_id))

    -- The three lines show draws above the rows: the title, the legend and a
    -- blank line.
    person_at = {}
    first_issue_line = 1
    for index, row in ipairs(rows) do
        if row.person then
            person_at[index + 3] = row.person
        end
        if row.key and first_issue_line == 1 then
            first_issue_line = index + 3
        end
    end

    show({
        name = BOARD,
        title = title,
        legend = legend,
        rows = rows,
        focus = focus,
        reload = function()
            cache.invalidate_prefix('board.')
            M.open()
        end,
    })
    paint_clock()
end

--- Shuffle `list[from..to]` in place.
---@param list any[]
---@param from integer
---@param to integer
local function shuffle(list, from, to)
    for index = to, from + 1, -1 do
        local other = math.random(from, index)
        list[index], list[other] = list[other], list[index]
    end
end

--- Everyone with an issue in the sprint, in a random order as the Jira standup
--- does, so the same person does not always speak first. The unassigned issues
--- come last, because nobody speaks for them.
---@param issues table[]
---@return qss.jira.Person[]
local function people_of(issues)
    local seen = {}
    local people = {}
    local unassigned = false

    for _, issue in ipairs(issues) do
        local assigned = assignee_of(issue)
        if not assigned then
            unassigned = true
        elseif not seen[assigned.accountId] then
            seen[assigned.accountId] = true
            people[#people + 1] = { id = assigned.accountId, name = assigned.displayName }
        end
    end

    shuffle(people, 1, #people)

    if unassigned then
        people[#people + 1] = { name = 'unassigned' }
    end
    return people
end

-- The countdown last asked for, offered again by the next prompt.
local last_countdown

--- `90`, `90s`, `2m`, `1m30` or `1:30`. Empty means no countdown.
---@param text string
---@return integer? seconds
local function parse_duration(text)
    text = vim.trim(text)
    if text == '' then
        return 0
    end
    local minutes, seconds = text:match('^(%d+):(%d%d?)$')
    if not minutes then
        minutes, seconds = text:match('^(%d+)m(%d*)s?$')
    end
    if minutes then
        return tonumber(minutes) * 60 + (tonumber(seconds) or 0)
    end
    seconds = text:match('^(%d+)s?$')
    return seconds and tonumber(seconds) or nil
end

---@param seconds integer
---@return string
local function format_duration(seconds)
    if seconds == 0 then
        return ''
    end
    local minutes, rest = math.floor(seconds / 60), seconds % 60
    if minutes == 0 then
        return ('%ds'):format(rest)
    end
    return rest == 0 and ('%dm'):format(minutes) or ('%dm%02d'):format(minutes, rest)
end

--- Run the countdown from now, or drop it with 0.
---@param current qss.jira.Standup
---@param seconds integer
local function set_countdown(current, seconds)
    last_countdown = seconds
    current.announced = false
    require('qss_nvim.jira.stop_sign').hide()

    if seconds == 0 then
        current.start_at = nil
        if current.timer then
            current.timer:close()
            current.timer = nil
        end
    else
        current.start_at = os.time() + seconds
        current.timer = current.timer or start_clock()
    end
    paint_clock()
end

--- Ask for a duration, asking again until the answer reads as one.
---@param what string
---@param offered integer seconds
---@param on_seconds fun(seconds: integer) not called when the prompt is cancelled
local function ask_duration(what, offered, on_seconds)
    vim.ui.input({
        prompt = ('%s (90, 2m, 1:30, empty for none): '):format(what),
        default = format_duration(offered),
    }, function(answer)
        if answer == nil then
            return
        end
        local seconds = parse_duration(answer)
        if not seconds then
            notify(('%s is not a duration'):format(answer), vim.log.levels.WARN)
            return ask_duration(what, offered, on_seconds)
        end
        on_seconds(seconds)
    end)
end

---@param current qss.jira.Standup
local function ask_countdown(current)
    local offered = last_countdown or config.options.standup_countdown or 0
    ask_duration('Countdown before the standup', offered, function(seconds)
        -- The standup ended or started while the prompt was up.
        if standup ~= current or current.since then
            return
        end
        set_countdown(current, seconds)
    end)
end

--- Change the time each person has. It applies to the person speaking too, so
--- raising it past what they have used hushes the sign.
function M.person_time()
    ask_duration('Time per person', person_limit(), function(seconds)
        person_time = seconds
        if standup and standup.person_since then
            local spoken = os.time() - standup.person_since
            if seconds == 0 or spoken < seconds then
                standup.person_announced = false
                require('qss_nvim.jira.stop_sign').hide()
            end
        end
        paint_clock()
    end)
end

--- Lay out the people without starting: nobody speaks and the clock stays at
--- rest until `>`, so the people who are not there can be marked first.
local function prepare_standup()
    standup_pending = false
    if not latest then
        return
    end

    local people = people_of(latest.issues)
    if #people == 0 then
        return notify('the sprint has no issue, so there is nobody to walk through', vim.log.levels.WARN)
    end

    standup = { people = people, index = 0 }
    draw(true)
    ask_countdown(standup)
end

--- Ask the countdown again, before the standup starts.
function M.countdown()
    if not standup then
        return notify('no standup is running. s starts one.', vim.log.levels.WARN)
    end
    if standup.since then
        return notify('the standup already started', vim.log.levels.WARN)
    end
    ask_countdown(standup)
end

local function end_standup()
    if not standup then
        return
    end
    local since = standup.since
    if standup.timer then
        standup.timer:close()
    end
    standup = nil
    require('qss_nvim.jira.stop_sign').hide()
    if since then
        notify(('the standup took %s'):format(clock(os.time() - since)), vim.log.levels.INFO)
    end
    draw(false)
end

--- The first person present from `from` on, walking by `by`.
---@param current qss.jira.Standup
---@param from integer
---@param by integer 1 or -1
---@return integer?
local function present_from(current, from, by)
    local index = from
    while current.people[index] do
        if not current.people[index].absent then
            return index
        end
        index = index + by
    end
    return nil
end

--- Hand the word to the first person present from `from` on. With nobody
--- present after the person speaking, the standup is over.
---@param current qss.jira.Standup
---@param from integer
local function give_word(current, from)
    local index = present_from(current, from, 1)
    if not index and not current.since then
        return notify('everybody is marked absent', vim.log.levels.WARN)
    end
    if not index then
        return end_standup()
    end

    local now = os.time()
    if not current.since then
        current.since = now
        current.timer = current.timer or start_clock()
    end
    require('qss_nvim.jira.stop_sign').hide()
    current.index = index
    current.person_since = now
    current.person_announced = false
    draw(false)

    -- The first issue of the new person, rather than wherever the cursor was
    -- left in a list that is now a different length.
    local buffer = existing_buffer(BOARD)
    if not buffer then
        return
    end
    local first = math.min(first_issue_line, vim.api.nvim_buf_line_count(buffer))
    for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
        vim.api.nvim_win_set_cursor(window, { first, 0 })
    end
end

--- Get a standup ready on the running sprint, or end the one in progress. It
--- starts on `>`.
function M.standup()
    if standup then
        return end_standup()
    end
    if latest and existing_buffer(BOARD) then
        return prepare_standup()
    end
    standup_pending = true
    M.open()
end

--- Draw a new order for the people who have not spoken yet. Whoever spoke and
--- whoever is speaking keep their place, and the unassigned issues stay last.
function M.shuffle()
    if not standup then
        return notify('no standup is running. s starts one.', vim.log.levels.WARN)
    end

    local people = standup.people
    local last = people[#people].id == nil and #people - 1 or #people
    if last - standup.index < 2 then
        return notify('nobody is left to shuffle', vim.log.levels.INFO)
    end
    shuffle(people, standup.index + 1, last)
    draw(false)
end

--- Hand the word to the next person present, or back to the previous one. Past
--- the last person, the standup is over.
---@param by integer
function M.step(by)
    if not standup then
        return notify('no standup is running. s starts one.', vim.log.levels.WARN)
    end

    if by > 0 then
        return give_word(standup, standup.index + 1)
    end
    local index = present_from(standup, standup.index - 1, -1)
    if index then
        give_word(standup, index)
    end
end

--- Mark the person on the line under the cursor absent, or back if they were.
--- Off the list, it acts on the person speaking. An absent speaker hands the
--- word on, and someone back after their turn went by speaks next.
function M.toggle_absent()
    if not standup then
        return notify('no standup is running. s starts one.', vim.log.levels.WARN)
    end

    local index = person_at[vim.api.nvim_win_get_cursor(0)[1]] or standup.index
    local person = standup.people[index]
    if not person then
        return notify('nobody speaks yet. Put the cursor on a person.', vim.log.levels.WARN)
    end

    if not person.absent then
        person.absent = true
        if index == standup.index then
            return give_word(standup, index + 1)
        end
        return draw(false)
    end

    person.absent = false
    if index < standup.index then
        table.remove(standup.people, index)
        standup.index = standup.index - 1
        table.insert(standup.people, standup.index + 1, person)
    end
    draw(false)
end

--- Redraw whichever list view is on screen, and only those.
function M.refresh()
    if existing_buffer(BOARD) then
        M.open({ focus = false })
    end
    if existing_buffer(BACKLOG) then
        M.backlog({ focus = false })
    end
end

--- Draw the running sprint, one section per board column.
---@param options { focus: boolean? }? focus defaults to true
function M.open(options)
    -- The buffer is claimed before anything is fetched. Fetching first and
    -- opening the name afterwards means the protocol loads it a second time,
    -- and every request is made twice.
    if not existing_buffer(BOARD) then
        return vim.cmd.edit(vim.fn.fnameescape(BOARD))
    end

    with_board(function(board_id)
        columns_of(board_id, function(columns)
            active_sprint(board_id, function(sprint)
                sprint_issues(board_id, sprint.id, function(issues)
                    local focus = not (options and options.focus == false)
                    with_account(function(account_id)
                        latest = { columns = columns, issues = issues, account_id = account_id, sprint = sprint }
                        if standup_pending then
                            return prepare_standup()
                        end
                        draw(focus)
                    end)
                end)
            end)
        end)
    end)
end

--- Every page of the board backlog. The agile API caps a page at 100 or so, and
--- a backlog is routinely longer than that, so it is read to the end rather than
--- cut off at a number that would hide whatever sits below it.
---@param board_id string
---@param callback fun(issues: table[])
local function all_backlog(board_id, callback)
    local issues = {}

    local function page(start_at)
        local path = ('/rest/agile/1.0/board/%s/backlog?startAt=%d&maxResults=100&fields=summary,status,assignee,issuetype')
            :format(board_id, start_at)

        http.jira_rest(path, function(decoded)
            local batch = decoded.issues or {}
            vim.list_extend(issues, batch)

            local total = decoded.total
            local more = #batch > 0 and (total == nil or #issues < total)
            if more then
                return page(start_at + #batch)
            end
            callback(issues)
        end)
    end

    page(0)
end

--- The backlog in its own order. A board column groups a sprint by status; a
--- backlog is ranked, and that rank is the whole point of it, so the rows stay
--- in the order the board returns them and carry their status instead.
---@param issues table[]
---@param account_id string?
---@return qss.jira.BoardRow[]
local function backlog_rows(issues, account_id)
    local rows = {}

    for _, issue in ipairs(issues) do
        local fields = issue.fields
        local assigned = assignee_of(issue)
        local assignee = assigned and assigned.displayName or 'unassigned'
        local mine = account_id ~= nil and assigned ~= nil and assigned.accountId == account_id

        local marker = mine and '▌' or ' '
        local prefix = ('%s %-11s'):format(marker, issue.key)
        local middle = ('%-16s %-12s %-22s '):format(
            fields.status.name:sub(1, 16), fields.issuetype.name:sub(1, 12), assignee:sub(1, 22))

        rows[#rows + 1] = {
            text = ('%s %s%s'):format(prefix, middle, fields.summary),
            key = issue.key,
            mine = mine,
            key_col = #marker + 1,
            dim_to = #prefix + 1 + #middle,
        }
    end

    return rows
end

--- Draw the backlog of the board.
---@param options { focus: boolean? }? focus defaults to true
function M.backlog(options)
    if not existing_buffer(BACKLOG) then
        return vim.cmd.edit(vim.fn.fnameescape(BACKLOG))
    end

    with_board(function(board_id)
        all_backlog(board_id, function(issues)
            with_account(function(account_id)
                show({
                    name = BACKLOG,
                    title = ('Backlog of %s  (%d issues)'):format(
                        config.instance().board or board_id, #issues),
                    rows = backlog_rows(issues, account_id),
                    focus = not (options and options.focus == false),
                    reload = function()
                        M.backlog()
                    end,
                })
            end)
        end)
    end)
end

return M
