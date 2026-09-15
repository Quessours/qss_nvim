-- The pickers. Every list this module shows is a snacks source, so the keys,
-- the matcher and the layout are the ones already in use everywhere else.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local cli = require('qss_nvim.jira.cli')
local config = require('qss_nvim.jira.config')
local http = require('qss_nvim.jira.http')

-- A workflow names its own statuses, so the match is on what the name contains
-- rather than on a fixed list. Anything unmatched keeps the normal colour.
local STATUS_HIGHLIGHTS = {
    { pattern = 'done',        group = 'DiagnosticOk' },
    { pattern = 'closed',      group = 'DiagnosticOk' },
    { pattern = 'resolved',    group = 'DiagnosticOk' },
    { pattern = 'progress',    group = 'DiagnosticWarn' },
    { pattern = 'review',      group = 'DiagnosticWarn' },
    { pattern = 'test',        group = 'DiagnosticInfo' },
    { pattern = 'blocked',     group = 'DiagnosticError' },
    { pattern = 'to do',       group = 'DiagnosticHint' },
    { pattern = 'backlog',     group = 'DiagnosticHint' },
}

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param status string
---@return string
local function status_highlight(status)
    local lowered = status:lower()
    for _, rule in ipairs(STATUS_HIGHLIGHTS) do
        if lowered:find(rule.pattern, 1, true) then
            return rule.group
        end
    end
    return 'SnacksPickerComment'
end

---@param issues table[]
---@return snacks.picker.finder.Item[]
local function to_items(issues)
    local items = {}
    for index, issue in ipairs(issues) do
        local fields = issue.fields or {}
        local status = fields.status and fields.status.name or 'unknown'
        -- `issue list --raw` prints jira-cli's own struct, which spells the type
        -- issueType and leaves the numeric id out; `issue view --raw` prints
        -- what the API returned, where the same thing is issuetype.
        local issue_type = fields.issueType or fields.issuetype
        local kind = issue_type and issue_type.name or ''
        -- An unassigned issue arrives as a displayName of "", not as no object.
        local who = fields.assignee and fields.assignee.displayName or ''
        local assignee = who ~= '' and who or 'unassigned'
        local summary = fields.summary or ''

        items[#items + 1] = {
            -- What the matcher types against: key, summary, status and type all.
            text = ('%s %s %s %s'):format(issue.key, summary, status, kind),
            idx = index,
            key = issue.key,
            summary = summary,
            status = status,
            kind = kind,
            assignee = assignee,
        }
    end
    return items
end

---@param item snacks.picker.Item
---@return snacks.picker.Highlight[]
local function format_issue(item)
    return {
        { ('%-12s'):format(item.key), 'SnacksPickerLabel' },
        { ' ' },
        { ('%-14s'):format(item.status:sub(1, 14)), status_highlight(item.status) },
        { ' ' },
        { item.summary },
        { ' ' },
        { ('(%s)'):format(item.assignee), 'SnacksPickerComment' },
    }
end

--- A Jira search, through jira-cli, remembered for as long as the answer is
--- likely to hold.
---@param cache_key string
---@param args string[]
---@param callback fun(issues: table[])
local function search(cache_key, args, callback)
    local remembered = cache.get(cache_key)
    if remembered then
        return callback(remembered)
    end

    cli.json(args, function(decoded)
        local issues = decoded.issues or decoded
        if type(issues) ~= 'table' then
            return notify('jira returned no issue list', vim.log.levels.ERROR)
        end
        cache.set(cache_key, issues, config.options.cache_ttl)
        callback(issues)
    end)
end

---@class qss.jira.PickerOptions
---@field title string
---@field cache_key string
---@field args string[]? a jira-cli query
---@field fetch fun(callback: fun(issues: table[]))? anything that is not jira-cli
---@field on_confirm fun(key: string)? replaces the action menu

--- The shared issue picker. Every entry point differs only by where its issues
--- come from.
---@param options qss.jira.PickerOptions
local function pick_issues(options)
    local fetch = options.fetch or function(callback)
        search(options.cache_key, options.args, callback)
    end

    fetch(function(issues)
        if #issues == 0 then
            return notify(('%s: nothing to show'):format(options.title), vim.log.levels.WARN)
        end

        local function on_item(picker, item, action)
            picker:close()
            if not item then
                return
            end
            action(item)
        end

        Snacks.picker({
            source = 'jira_issues',
            items = to_items(issues),
            format = format_issue,
            title = options.title,
            actions = {
                jira_yank = function(picker, item)
                    on_item(picker, item, function(chosen)
                        vim.fn.setreg('+', chosen.key)
                        notify(('yanked %s'):format(chosen.key), vim.log.levels.INFO)
                    end)
                end,
                jira_transition = function(picker, item)
                    on_item(picker, item, function(chosen)
                        M.transition(chosen.key)
                    end)
                end,
                jira_start = function(picker, item)
                    on_item(picker, item, function(chosen)
                        require('qss_nvim.jira.work').start(chosen.key, chosen.summary)
                    end)
                end,
                jira_refresh = function(picker)
                    picker:close()
                    cache.invalidate(options.cache_key)
                    pick_issues(options)
                end,
                -- <C-q> is where a picker sends things in this editor. The
                -- entries point at jira:// addresses, so :cnext opens the next
                -- ticket rather than only naming it, and the list survives the
                -- picker being closed.
                jira_quickfix = function(picker)
                    local selected = picker:selected({ fallback = false })
                    local chosen = #selected > 0 and selected or picker:items()
                    picker:close()

                    local entries = {}
                    for _, item in ipairs(chosen) do
                        entries[#entries + 1] = {
                            filename = ('jira://%s'):format(item.key),
                            lnum = 1,
                            col = 1,
                            text = ('[%s] %s'):format(item.status, item.summary),
                        }
                    end

                    vim.fn.setqflist({}, ' ', { title = options.title, items = entries })
                    vim.cmd.copen()
                    notify(('%d issues in the quickfix list'):format(#entries), vim.log.levels.INFO)
                end,
            },
            win = {
                input = {
                    keys = {
                        ['<c-y>'] = { 'jira_yank', mode = { 'n', 'i' } },
                        ['<c-t>'] = { 'jira_transition', mode = { 'n', 'i' } },
                        ['<c-s>'] = { 'jira_start', mode = { 'n', 'i' } },
                        ['<c-r>'] = { 'jira_refresh', mode = { 'n', 'i' } },
                        ['<c-q>'] = { 'jira_quickfix', mode = { 'n', 'i' } },
                    },
                },
                list = {
                    keys = {
                        ['<c-y>'] = 'jira_yank',
                        ['<c-t>'] = 'jira_transition',
                        ['<c-s>'] = 'jira_start',
                        ['<c-r>'] = 'jira_refresh',
                        ['<c-q>'] = 'jira_quickfix',
                    },
                },
            },
            confirm = function(picker, item)
                on_item(picker, item, function(chosen)
                    if options.on_confirm then
                        return options.on_confirm(chosen.key)
                    end
                    require('qss_nvim.jira.actions').menu(chosen.key, chosen.summary)
                end)
            end,
        })
    end)
end

--- The issues of the open sprints, assigned to you.
---@param options { on_confirm: fun(key: string)? }?
function M.issues(options)
    pick_issues({
        title = 'Jira sprint',
        cache_key = 'issues.sprint',
        args = { 'issue', 'list', '--paginate', '100',
            '-q', 'sprint in openSprints() AND assignee = currentUser() AND resolution = Unresolved' },
        on_confirm = options and options.on_confirm,
    })
end

--- Every unresolved issue of the project.
---@param options { on_confirm: fun(key: string)? }?
function M.all_issues(options)
    pick_issues({
        title = 'Jira project',
        cache_key = 'issues.project',
        args = { 'issue', 'list', '--paginate', '100', '-q', 'resolution = Unresolved' },
        on_confirm = options and options.on_confirm,
    })
end

--- The epics of the project.
---@param options { on_confirm: fun(key: string)? }?
function M.epics(options)
    pick_issues({
        title = 'Jira epics',
        cache_key = 'issues.epics',
        args = { 'epic', 'list', '--paginate', '100' },
        on_confirm = options and options.on_confirm,
    })
end

--- The issues of one epic.
---@param key string
function M.epic_issues(key)
    pick_issues({
        title = ('Jira epic %s'):format(key),
        cache_key = ('issues.epic.%s'):format(key),
        args = { 'epic', 'list', key, '--paginate', '100' },
    })
end

--- Move an issue. The list is not remembered: which moves exist depends on the
--- status the issue is in right now, so a stale list offers moves that fail.
---
--- The move is sent as a transition id rather than through `jira issue move`,
--- because a transition can be named differently from the status it leads to
--- (this workflow has "To Test" landing on "To Accept"), and a name is then
--- ambiguous where an id never is.
---@param key string
---@param callback fun()? runs once the move landed
function M.transition(key, callback)
    local path = ('/rest/api/3/issue/%s/transitions'):format(key)

    http.jira_rest(path, function(decoded)
        local transitions = decoded.transitions or {}
        if #transitions == 0 then
            return notify(('%s can not move anywhere from here'):format(key), vim.log.levels.WARN)
        end

        local items = {}
        for index, transition in ipairs(transitions) do
            local target = transition.to and transition.to.name or transition.name
            local label = target == transition.name
                and target
                or ('%s  (%s)'):format(target, transition.name)
            items[#items + 1] = {
                text = label,
                transition_id = transition.id,
                target = target,
                idx = index,
            }
        end

        Snacks.picker({
            source = 'jira_transitions',
            items = items,
            format = 'text',
            title = ('Move %s to'):format(key),
            layout = { preset = 'select' },
            confirm = function(picker, item)
                picker:close()
                if not item then
                    return
                end
                http.jira_post(path, { transition = { id = item.transition_id } }, function()
                    require('qss_nvim.jira.edit').landed(key)
                    notify(('%s is now %s'):format(key, item.target), vim.log.levels.INFO)
                    if callback then
                        callback()
                    end
                end)
            end,
        })
    end)
end

--- The sprints of the board. `sprint list` ignores --raw and prints its table
--- either way, so the table is what gets read: id, name, then the state last.
---@param state string for example active, or active,future
---@param callback fun(sprints: { id: string, name: string, state: string }[])
function M.list_sprints(state, callback)
    cli.run({ 'sprint', 'list', '--state', state, '--plain', '--no-headers' }, function(stdout)
        local sprints = {}
        for _, line in ipairs(vim.split(stdout, '\n', { plain = true })) do
            local columns = vim.split(line, '\t', { plain = true })
            local id = vim.trim(columns[1] or '')
            local name = vim.trim(columns[2] or '')
            if id:match('^%d+$') and name ~= '' then
                sprints[#sprints + 1] = {
                    id = id,
                    name = name,
                    state = vim.trim(columns[#columns] or ''),
                }
            end
        end
        callback(sprints)
    end)
end

--- The sprints an issue can be moved into.
---@param callback fun(sprint: { id: string, name: string })
function M.sprints(callback)
    M.list_sprints('active,future', function(sprints)
        if #sprints == 0 then
            return notify('no active or future sprint on the board', vim.log.levels.WARN)
        end

        local items = {}
        for index, sprint in ipairs(sprints) do
            items[#items + 1] = {
                text = ('%-20s %s'):format(sprint.name, sprint.state),
                sprint = sprint,
                idx = index,
            }
        end

        Snacks.picker({
            source = 'jira_sprints',
            items = items,
            format = 'text',
            title = 'Sprint',
            layout = { preset = 'select' },
            confirm = function(picker, item)
                picker:close()
                if item then
                    callback(item.sprint)
                end
            end,
        })
    end)
end

--- The backlog of the board: what the board holds outside every sprint. The
--- agile API is asked rather than a JQL of "sprint is EMPTY", because the
--- backlog is whatever the board filter says it is, not whatever the project
--- holds.
---@param options { on_confirm: fun(key: string)? }?
function M.backlog(options)
    local instance = config.instance()
    if not (instance and instance.board_id) then
        return notify('the board id is missing from the jira-cli config. Re-run jira init.',
            vim.log.levels.ERROR)
    end

    local cache_key = ('issues.backlog.%s'):format(instance.board_id)

    pick_issues({
        title = ('Backlog of %s'):format(instance.board),
        cache_key = cache_key,
        on_confirm = options and options.on_confirm,
        fetch = function(callback)
            local remembered = cache.get(cache_key)
            if remembered then
                return callback(remembered)
            end

            local limit = 200
            local path = ('/rest/agile/1.0/board/%s/backlog?maxResults=%d&fields=summary,status,assignee,issuetype')
                :format(instance.board_id, limit)

            http.jira_rest(path, function(decoded)
                local issues = decoded.issues or {}
                if #issues >= limit then
                    notify(('the backlog is longer than %d issues; narrow it with <leader>jq'):format(limit),
                        vim.log.levels.WARN)
                end
                cache.set(cache_key, issues, config.options.cache_ttl)
                callback(issues)
            end)
        end,
    })
end

--- The queries typed before, newest first.
---@return string[]
local function jql_history()
    return cache.get('jql.history') or {}
end

---@param query string
local function remember_jql(query)
    local history = { query }
    for _, previous in ipairs(jql_history()) do
        if previous ~= query and #history < 20 then
            history[#history + 1] = previous
        end
    end
    cache.set('jql.history', history)
end

--- Run a JQL query. jira-cli adds its own project scope and its own ORDER BY,
--- so the query given here must carry neither.
---@param query string
---@param options { on_confirm: fun(key: string)? }?
function M.jql(query, options)
    remember_jql(query)
    pick_issues({
        title = query,
        cache_key = ('issues.jql.%s'):format(query),
        args = { 'issue', 'list', '--paginate', '100', '-q', query },
        on_confirm = options and options.on_confirm,
    })
end

--- Ask for a query, starting from the last one.
function M.ask_jql()
    local history = jql_history()
    Snacks.input({ prompt = 'JQL: ', default = history[1] or 'resolution = Unresolved' }, function(answer)
        local query = answer and vim.trim(answer) or ''
        if query == '' then
            return
        end
        M.jql(query)
    end)
end

--- Pick among the queries already used.
function M.jql_history()
    local history = jql_history()
    if #history == 0 then
        return notify('no query has been run yet', vim.log.levels.INFO)
    end

    local items = {}
    for index, query in ipairs(history) do
        items[#items + 1] = { text = query, idx = index }
    end

    Snacks.picker({
        source = 'jira_jql_history',
        items = items,
        format = 'text',
        title = 'Queries already run',
        layout = { preset = 'select' },
        confirm = function(picker, item)
            picker:close()
            if item then
                M.jql(item.text)
            end
        end,
    })
end

--- A term, safe to put inside a quoted JQL string.
---@param term string
---@return string
local function quoted(term)
    return (term:gsub('\\', '\\\\'):gsub('"', '\\"'))
end

--- Free text search across the project. `text ~` covers the summary, the
--- description, the comments and the text custom fields, which is what someone
--- typing a few words is after. A single word gets a trailing star, because Jira
--- matches whole words otherwise and "setting" would miss "settings".
---@param term string
---@param options { on_confirm: fun(key: string)? }?
function M.search(term, options)
    local pattern = term:find('%s') and quoted(term) or (quoted(term) .. '*')

    pick_issues({
        title = ('Search: %s'):format(term),
        cache_key = ('issues.search.%s'):format(term),
        args = { 'issue', 'list', '--paginate', '100', '-q', ('text ~ "%s"'):format(pattern) },
        on_confirm = options and options.on_confirm,
    })
end

return M
