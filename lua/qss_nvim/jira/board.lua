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
    local path = ('/rest/agile/1.0/board/%s/sprint/%d/issue?maxResults=200&fields=summary,status,assignee,issuetype,priority')
        :format(board_id, sprint_id)

    http.jira_rest(path, function(decoded)
        callback(decoded.issues or {})
    end)
end

---@class qss.jira.BoardRow
---@field text string
---@field key string? absent on a heading or a blank line
---@field mine boolean
---@field key_col integer? byte offset of the key
---@field dim_to integer? byte offset where the summary starts

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
            local assigned = type(fields.assignee) == 'table' and fields.assignee or nil
            local assignee = assigned and assigned.displayName or 'unassigned'
            local mine = account_id ~= nil and assigned ~= nil and assigned.accountId == account_id

            -- The offsets are taken here rather than guessed back out of the
            -- line: a marker or an accent is more than one byte wide, and an
            -- extmark counts bytes.
            local marker = mine and '▌' or ' '
            local prefix = ('%s %-11s'):format(marker, issue.key)
            local middle = ('%-14s %-20s '):format(fields.issuetype.name:sub(1, 14), assignee:sub(1, 20))

            rows[#rows + 1] = {
                text = ('%s %s%s'):format(prefix, middle, fields.summary),
                key = issue.key,
                mine = mine,
                key_col = #marker + 1,
                dim_to = #prefix + 1 + #middle,
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

    for index, row in ipairs(rows) do
        if row.key then
            local line = index - 1 + offset
            vim.api.nvim_buf_set_extmark(buffer, namespace, line, row.key_col, {
                end_col = row.key_col + #row.key,
                hl_group = row.mine and 'DiagnosticOk' or 'Identifier',
            })
            vim.api.nvim_buf_set_extmark(buffer, namespace, line, row.key_col + #row.key, {
                end_col = math.min(row.dim_to, #row.text),
                hl_group = 'Comment',
            })
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
        '  i or <CR> acts   e, v or gd open   t transition   o browser   y yank   r reload   q close',
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
    M.open({ focus = false })
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
                        show({
                            name = BOARD,
                            title = ('%s  (%d issues)'):format(sprint.name, #issues),
                            rows = rows_of(columns, issues, account_id),
                            focus = focus,
                            reload = function()
                                cache.invalidate_prefix('board.')
                                M.open()
                            end,
                        })
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
        local assigned = type(fields.assignee) == 'table' and fields.assignee or nil
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
