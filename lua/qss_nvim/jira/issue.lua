-- One issue, drawn by this module rather than by `jira issue view --plain`, so
-- that every field sits on a line of its own and the line knows which field it
-- is. That is what lets `i` edit the field under the cursor, the way `i` starts
-- an edit anywhere else in the editor.
--
-- The buffer holds prose, so no other single letter is bound: `w`, `e`, `l`,
-- `y`, `f` and `t` stay the motions they are everywhere else.
local M = {}

local TITLE = 'Jira'

local adf = require('qss_nvim.jira.adf')
local cli = require('qss_nvim.jira.cli')
local config = require('qss_nvim.jira.config')
local edit = require('qss_nvim.jira.edit')
local fields_module = require('qss_nvim.jira.fields')
local utils = require('qss_nvim.utils')

local namespace = vim.api.nvim_create_namespace('qss.jira.issue')

-- Where following a link came from. The tag stack is the shape vim already has
-- for this: <C-]> goes in, <C-t> comes back out. The window's own jump list is
-- not used, because switching buffers by hand records no jump and <C-t> would
-- have nothing to pop.
---@type string[]
local came_from = {}

-- Shown first, in this order, because they are what a reader looks for. Status
-- is not a field: it moves through a transition.
local LEADING = { 'status', 'assignee', 'priority', 'labels', 'summary' }
-- Neither is the sprint, which moves through the board.
local SKIPPED = {
    customfield_10005 = true,
    description = true,
    attachment = true,
    comment = true,
    -- Links have a section of their own, where each one can be followed or cut.
    issuelinks = true,
}

local LABEL_WIDTH = 26

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param key string
---@return string
local function buffer_name(key)
    return ('jira://%s'):format(key)
end

---@param name string
---@return integer?
local function find_buffer(name)
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer):sub(-#name) == name then
            return buffer
        end
    end
    return nil
end

--- What one line of the buffer is about. Exactly one of these is set, and every
--- line of the buffer has one, so `i` never lands on nothing.
---@class qss.jira.Line
---@field field qss.jira.EditField? a field to edit
---@field current any the value that field holds
---@field link qss.jira.Link? a link to follow or cut
---@field comment table? a comment to edit or delete
---@field add_link boolean? the Links heading
---@field add_comment boolean? the Comments heading

--- The lines of the buffer, and which field each editable one carries.
--- The estimates, which Jira keeps as one field and reports in three places.
---@param values table
---@return string
local function estimates(values)
    local tracking = type(values.timetracking) == 'table' and values.timetracking or {}
    local original = tracking.originalEstimate
    local remaining = tracking.remainingEstimate
    local spent = tracking.timeSpent

    if not (original or remaining or spent) then
        return ''
    end
    return ('original %s · remaining %s · spent %s'):format(
        original or '—', remaining or '—', spent or '—')
end

---@param key string
---@param issue table
---@param editable qss.jira.EditField[]
---@param comments table[]
---@return string[] lines, table<integer, qss.jira.Line> owners
local function render(key, issue, editable, comments)
    local values = issue.fields or {}
    local lines = {}
    local owners = {}

    ---@param label string
    ---@param value string
    ---@param owner qss.jira.Line?
    local function row(label, value, owner)
        lines[#lines + 1] = ('  %-' .. LABEL_WIDTH .. 's%s'):format(label:sub(1, LABEL_WIDTH - 1),
            value ~= '' and value or '—')
        if owner then
            owners[#lines] = owner
        end
    end

    lines[#lines + 1] = ('# %s  %s'):format(key, values.summary or '')
    -- The title opens the whole menu, which is the answer to "what can I do
    -- here" when the cursor is not on anything narrower.
    owners[1] = {}
    lines[#lines + 1] = '  i or <CR> acts on this line · gd follows an issue · <C-t> comes back · q closes'
    lines[#lines + 1] = ''

    local by_id = {}
    for _, field in ipairs(editable) do
        by_id[field.id] = field
    end

    local drawn = {}
    row('Status', values.status and values.status.name or '',
        { field = { id = 'status', name = 'Status', type = 'transition', operations = {} } })
    row('Type', values.issuetype and values.issuetype.name or '')
    row('Reporter', values.reporter and values.reporter.displayName or '')

    for _, id in ipairs(LEADING) do
        local field = by_id[id]
        if field then
            drawn[id] = true
            row(field.name, fields_module.render(values[id]), { field = field, current = values[id] })
        end
    end

    -- The estimates are shown whether or not the workflow lets this issue carry
    -- them, because "no estimate" is itself worth reading. The line only becomes
    -- editable when editmeta says the field is writable here.
    drawn.timetracking = true
    local tracking = by_id.timetracking
    row('Estimate', estimates(values),
        tracking and { field = tracking, current = values.timetracking } or nil)

    -- The sprint moves through the board rather than through a field, which the
    -- prompt behind this row knows. It is still a row, because reading the
    -- sprint and changing it belong in the same place.
    local in_sprint = by_id.customfield_10005
    local sprint = fields_module.render(values.customfield_10005)
    if sprint ~= '' then
        row('Sprint', sprint,
            in_sprint and { field = in_sprint, current = values.customfield_10005 } or nil)
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = '## Fields'
    lines[#lines + 1] = ''

    local filled = {}
    local empty = {}
    for _, field in ipairs(editable) do
        if not (drawn[field.id] or SKIPPED[field.id] or config.is_hidden(field.name)) then
            local held = fields_module.render(values[field.id])
            -- Jira reports an untouched object field as the literal "{}".
            local entry = { field = field, value = (held == '{}' or held == '[]') and '' or held }
            local bucket = entry.value ~= '' and filled or empty
            bucket[#bucket + 1] = entry
        end
    end
    vim.list_extend(filled, empty)
    for _, entry in ipairs(filled) do
        row(entry.field.name, entry.value, { field = entry.field, current = values[entry.field.id] })
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = '## Description'
    lines[#lines + 1] = ''

    local description_heading = #lines - 1
    local description_line = #lines + 1
    local body, kept = adf.to_markdown(values.description)
    vim.list_extend(lines, body)

    local description_field = by_id.description
        or { id = 'description', name = 'Description', type = 'string', operations = {} }
    for line = description_heading, #lines do
        owners[line] = { field = description_field, current = values.description }
    end
    if #kept > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('  %d block above is kept as it is; markdown can not write it.'):format(#kept)
    end

    local links = require('qss_nvim.jira.links').of(values)
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('## Links  (%d)'):format(#links)
    owners[#lines] = { add_link = true }
    lines[#lines + 1] = ''

    for _, link in ipairs(links) do
        lines[#lines + 1] = ('  %-26s %-11s %-14s %s'):format(link.phrase, link.other,
            link.status:sub(1, 14), link.summary)
        owners[#lines] = { link = link }
    end
    if #links == 0 then
        lines[#lines + 1] = '  none yet'
        owners[#lines] = { add_link = true }
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = ('## Comments  (%d)'):format(#comments)
    owners[#lines] = { add_comment = true }
    lines[#lines + 1] = ''

    if #comments == 0 then
        lines[#lines + 1] = '  none yet'
        owners[#lines] = { add_comment = true }
    end

    for _, comment in ipairs(comments) do
        local opened = #lines + 1
        lines[#lines + 1] = ('### %s  ·  %s'):format(comment.author and comment.author.displayName or '?',
            (comment.created or ''):sub(1, 10))
        lines[#lines + 1] = ''
        vim.list_extend(lines, (adf.to_markdown(comment.body)))
        -- The whole block belongs to its comment, so the cursor does not have to
        -- find the header line to act on what it is reading.
        for line = opened, #lines do
            owners[line] = { comment = comment }
        end
    end

    return lines, owners
end

---@param buffer integer
---@param lines string[]
---@param owners table<integer, qss.jira.Line>
local function paint(buffer, lines, owners)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

    for line, owner in pairs(owners) do
        local text = lines[line]
        if not owner.field or owner.link or owner.comment then
            goto continue
        end
        if text and text:sub(1, 2) == '  ' and owner.field.type ~= 'string' or text and text:sub(1, 2) == '  ' then
            vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, 2, {
                end_col = math.min(2 + LABEL_WIDTH, #text),
                hl_group = 'SnacksPickerLabel',
            })
        end
        ::continue::
    end
end

--- Prepare a buffer nvim has just made for a `jira://` name.
---@param buffer integer
---@param key string
function M.prepare(buffer, key)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'hide'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
    vim.b[buffer].qss_jira_key = key
    vim.b[buffer].qss_jira_view = 'issue'
    vim.bo[buffer].filetype = 'jira'
end

---@param buffer integer
---@param key string
function M.bind_keys(buffer, key)
    -- One gesture for the whole buffer: act on whatever the cursor is on. A line
    -- that is not a field, a link or a comment falls back to the issue menu
    -- rather than reporting that there is nothing here.
    local function act()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local owner = (vim.b[buffer].qss_jira_owners or {})[tostring(line)] or {}

        local function reload()
            M.open(key)
        end

        if owner.link then
            return require('qss_nvim.jira.links').menu(key, owner.link, reload)
        end
        if owner.comment then
            return require('qss_nvim.jira.actions').comment_menu(key, owner.comment, reload)
        end
        if owner.add_link then
            return require('qss_nvim.jira.links').add(key, reload)
        end
        if owner.add_comment then
            return require('qss_nvim.jira.actions').add_comment(key)
        end
        if owner.field and owner.field.id == 'status' then
            return require('qss_nvim.jira.picker').transition(key, reload)
        end
        if owner.field then
            return edit.field(key, owner.field, owner.current, reload)
        end
        require('qss_nvim.jira.actions').menu(key)
    end

    vim.keymap.set('n', 'i', act, { buffer = buffer, desc = 'Act on what is under the cursor' })
    vim.keymap.set('n', '<CR>', act, { buffer = buffer, desc = 'Act on what is under the cursor' })

    -- Following a link is a jump, so it is bound where a jump is bound: gd and
    -- <C-]> go, and <C-o> comes back, because M.open pushes the jumplist first.
    -- A link row is about one issue from end to end, so following it must not
    -- depend on the cursor sitting exactly on the key. Elsewhere the cursor
    -- decides, which is what tells two keys on one line apart.
    local function follow()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local owner = (vim.b[buffer].qss_jira_owners or {})[tostring(line)] or {}

        local there = owner.link and owner.link.other or M.key_under_cursor()
        if not there then
            -- Last resort: the first key on the line that is not this issue.
            for found in vim.api.nvim_get_current_line():gmatch('%f[%w]%u[%u%d]*%-%d+') do
                if found ~= key then
                    there = found
                    break
                end
            end
        end

        if not there then
            return notify('no issue key on this line', vim.log.levels.WARN)
        end
        if there == key then
            return notify('this is already the issue on screen', vim.log.levels.INFO)
        end
        came_from[#came_from + 1] = key
        M.open(there)
    end

    local function back()
        local previous = table.remove(came_from)
        if not previous then
            return notify('nothing to come back to', vim.log.levels.INFO)
        end
        M.open(previous)
    end

    vim.keymap.set('n', 'gd', follow, { buffer = buffer, desc = 'Go to the issue under the cursor' })
    vim.keymap.set('n', '<C-]>', follow, { buffer = buffer, desc = 'Go to the issue under the cursor' })
    vim.keymap.set('n', '<C-t>', back, { buffer = buffer, desc = 'Back to the issue you came from' })

end

--- Fill a buffer with an issue. The buffer already exists: either nvim made it
--- for a `jira://` name, or a redraw is writing over the one on screen.
---@param buffer integer
---@param key string
function M.load(buffer, key)
    local issue
    local editable
    local comments

    local function draw()
        if not (issue and editable and comments) then
            return
        end
        if not vim.api.nvim_buf_is_valid(buffer) then
            return
        end

        local lines, owners = render(key, issue, editable, comments)

        -- A refresh redraws under the cursor, so the line being worked on stays
        -- the line under the cursor.
        local windows = vim.fn.win_findbuf(buffer)
        local cursors = {}
        for _, window in ipairs(windows) do
            cursors[window] = vim.api.nvim_win_get_cursor(window)
        end

        vim.bo[buffer].modifiable = true
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
        vim.bo[buffer].modifiable = false
        vim.bo[buffer].modified = false

        -- Keyed by string, because a buffer variable crosses into vimscript land
        -- and a sparse integer table does not survive the trip.
        local keyed = {}
        for line, owner in pairs(owners) do
            keyed[tostring(line)] = owner
        end
        vim.b[buffer].qss_jira_owners = keyed
        vim.b[buffer].qss_jira_key = key

        paint(buffer, lines, owners)

        for window, position in pairs(cursors) do
            if vim.api.nvim_win_is_valid(window) then
                vim.api.nvim_win_set_cursor(window, { math.min(position[1], #lines), position[2] })
            end
        end
    end

    cli.json({ 'issue', 'view', key }, function(decoded)
        issue = decoded
        draw()
    end)

    edit.editable(key, function(fields)
        editable = fields
        draw()
    end)

    -- The comments come from the API rather than from the issue jira-cli
    -- returns, which carries only the first one: its comment field arrives with
    -- maxResults of 1, so a conversation of ten reads as a conversation of one.
    require('qss_nvim.jira.http').jira_rest(
        ('/rest/api/3/issue/%s/comment?maxResults=100&orderBy=created'):format(key),
        function(decoded)
            comments = decoded.comments or {}
            draw()
        end)
end

--- Show an issue. Opening it is `:edit jira://KEY` and nothing more, so every
--- path nvim already has reaches it: gf on a key, a session being restored, a
--- quickfix entry, or the command line.
---@param key string
---@param options { focus: boolean? }? focus defaults to true
function M.open(key, options)
    local name = buffer_name(key)
    local existing = find_buffer(name)

    if options and options.focus == false then
        if existing then
            M.load(existing, key)
        end
        return
    end

    if existing and vim.api.nvim_get_current_buf() == existing then
        return M.load(existing, key)
    end

    local window = utils.main_window()
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_set_current_win(window)
    end
    vim.cmd.edit(vim.fn.fnameescape(name))
end

--- Redraw an issue, but only where one is already on screen. Called after every
--- change, so a view never shows a value that was edited a moment ago.
---@param key string
function M.refresh(key)
    if find_buffer(buffer_name(key)) then
        M.open(key, { focus = false })
    end
end

--- The issue the cursor sits in, for a buffer this module opened.
---@return string?
function M.current()
    return vim.b.qss_jira_key
end

--- The issue key the cursor is sitting on, wherever that is: a commit message, a
--- code comment, a log line, a branch listing. The match has to span the cursor,
--- so a line naming three issues resolves to the one being pointed at.
---@return string?
function M.key_under_cursor()
    local line = vim.api.nvim_get_current_line()
    local column = vim.api.nvim_win_get_cursor(0)[2] + 1

    local from = 1
    while true do
        local start, stop = line:find('%f[%w]%u[%u%d]*%-%d+', from)
        if not start then
            return nil
        end
        if column >= start and column <= stop then
            return line:sub(start, stop)
        end
        from = stop + 1
    end
end

--- The issue every keymap works on, in order: the one under the cursor, the one
--- this buffer shows, the one in the branch name. Without any of them, the
--- caller opens a picker instead.
---
--- The cursor comes first because pointing at something is the clearest way of
--- naming it. Reading LIS-2311 and logging an hour against the LIS-2228 named
--- in its links is an ordinary thing to want, and there is no other way to say
--- it. Every prompt names the issue it is about, so the choice is always
--- visible before anything is written.
---@return string?
function M.in_context()
    local pointed = M.key_under_cursor()
    if pointed then
        return pointed
    end

    -- A link row is about one issue from end to end, so standing anywhere on it
    -- names that issue. Without this, the cursor four columns left of the key
    -- would mean one ticket and gd on the same spot would mean another.
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local owner = (vim.b.qss_jira_owners or {})[tostring(line)]
    if owner and owner.link then
        return owner.link.other
    end

    local shown = M.current()
    if shown then
        return shown
    end
    return require('qss_nvim.jira.git').issue_key()
end

--- Find an issue: by key, by number alone, or by the words in it.
---
--- A key goes straight through. A bare number takes the project of the instance,
--- because "2431" is what a person reads off a branch or a commit. Anything else
--- is a search, which is the case a strict key prompt used to refuse outright.
---@param callback fun(key: string)
function M.find(callback)
    local project = (config.instance() or {}).project or ''

    Snacks.input({ prompt = 'Issue or words: ', default = M.in_context() or '' }, function(answer)
        local typed = answer and vim.trim(answer) or ''
        if typed == '' then
            return
        end

        local number = typed:match('^%d+$')
        if number and project ~= '' then
            return callback(('%s-%s'):format(project, number))
        end

        local key = typed:upper():match('^%u[%u%d]*%-%d+$')
        if key then
            return callback(key)
        end

        require('qss_nvim.jira.picker').search(typed, { on_confirm = callback })
    end)
end

--- Run something on the issue in context, or pick one first.
---@param callback fun(key: string)
function M.with_key(callback)
    local key = M.in_context()
    if key then
        return callback(key)
    end
    notify('no issue key in the branch name, so pick one', vim.log.levels.INFO)
    require('qss_nvim.jira.picker').issues({ on_confirm = callback })
end

return M
