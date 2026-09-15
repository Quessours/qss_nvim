-- A feature module rather than a plugin, in the shape of qt-class and cpp-impl:
-- required once from the root init.lua, registering its commands as it loads.
--
-- Creating an issue lives here because it is the one flow that has no issue key
-- to start from, so no other file in the directory is the right home for it.
local M = {}

local TITLE = 'Jira'

local actions = require('qss_nvim.jira.actions')
local cache = require('qss_nvim.jira.cache')
local cli = require('qss_nvim.jira.cli')
local config = require('qss_nvim.jira.config')
local git = require('qss_nvim.jira.git')
local issue = require('qss_nvim.jira.issue')
local picker = require('qss_nvim.jira.picker')

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- The keys already seen, for command completion. They come out of the lists
--- this session has loaded, so there is no extra call to make one work.
---@param lead string
---@return string[]
local function known_keys(lead)
    local seen = {}
    local keys = {}

    for _, name in ipairs({ 'issues.sprint', 'issues.project', 'issues.epics' }) do
        for _, listed in ipairs(cache.get(name) or {}) do
            local key = listed.key
            if key and not seen[key] and key:upper():find(lead:upper(), 1, true) == 1 then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end

    table.sort(keys)
    return keys
end

---@param kind string
---@param summary string
---@param body string
local function create_issue(kind, summary, body)
    local args = { 'issue', 'create', '--type', kind, '--summary', summary, '--body', body, '--no-input' }

    cli.run(args, function(stdout)
        local key = stdout:match('%f[%w]%u[%u%d]*%-%d+')
        cache.invalidate_prefix('issues.')

        if not key then
            return notify('the issue was created, but its key was not in the answer', vim.log.levels.WARN)
        end
        notify(('%s created'):format(key), vim.log.levels.INFO)
        actions.menu(key, summary)
    end)
end

--- Create an issue: type, then summary, then a markdown buffer for the body.
function M.create()
    local instance = config.instance()
    if not (instance and #instance.issue_types > 0) then
        return notify('jira-cli knows no issue type. Re-run jira init.', vim.log.levels.ERROR)
    end

    local items = {}
    for index, kind in ipairs(instance.issue_types) do
        items[#items + 1] = { text = kind, idx = index }
    end

    Snacks.picker({
        source = 'jira_issue_types',
        items = items,
        format = 'text',
        title = ('New issue in %s'):format(instance.project or '?'),
        layout = { preset = 'select' },
        confirm = function(chooser, chosen)
            chooser:close()
            if not chosen then
                return
            end

            Snacks.input({ prompt = ('%s summary: '):format(chosen.text) }, function(answer)
                local summary = answer and vim.trim(answer) or ''
                if summary == '' then
                    return
                end
                actions.compose({
                    title = ('Description of the new %s'):format(chosen.text),
                    initial = { '' },
                    on_submit = function(body)
                        create_issue(chosen.text, summary, body)
                    end,
                })
            end)
        end,
    })
end

require('qss_nvim.jira.protocol').setup()
git.setup_commit_buffer()

vim.api.nvim_create_user_command('JiraBoard', function()
    require('qss_nvim.jira.board').open()
end, {
    desc = 'Draw the running sprint as a board',
})

vim.api.nvim_create_user_command('JiraIssues', function()
    picker.issues()
end, {
    desc = 'Pick among the sprint issues assigned to you',
})

vim.api.nvim_create_user_command('JiraProject', function()
    picker.all_issues()
end, {
    desc = 'Pick among the unresolved issues of the project',
})

vim.api.nvim_create_user_command('JiraEpics', function()
    picker.epics()
end, {
    desc = 'Pick among the epics of the project',
})

vim.api.nvim_create_user_command('JiraSprint', function()
    require('qss_nvim.jira.sprint').open()
end, {
    desc = 'Sprint report and burndown of the running sprint',
})

vim.api.nvim_create_user_command('JiraSprintPick', function()
    require('qss_nvim.jira.sprint').pick()
end, {
    desc = 'Sprint report and burndown of any sprint',
})

vim.api.nvim_create_user_command('JiraBacklog', function()
    require('qss_nvim.jira.board').backlog()
end, {
    desc = 'Draw the backlog of the board',
})

vim.api.nvim_create_user_command('JiraBacklogSearch', function()
    picker.backlog()
end, {
    desc = 'Fuzzy find in the backlog of the board',
})

vim.api.nvim_create_user_command('JiraQuickfix', function(opts)
    local query = vim.trim(opts.args)
    if query == '' then
        return picker.ask_jql()
    end
    picker.jql(query)
end, {
    nargs = '?',
    desc = 'Run a JQL query, then <C-q> to send the results to the quickfix list',
})

vim.api.nvim_create_user_command('JiraJql', function(opts)
    local query = vim.trim(opts.args)
    if query ~= '' then
        return picker.jql(query)
    end
    picker.ask_jql()
end, {
    nargs = '?',
    desc = 'Pick among the issues a JQL query returns',
})

vim.api.nvim_create_user_command('JiraView', function(opts)
    local argument = vim.trim(opts.args)
    if argument ~= '' then
        return issue.open(argument:upper())
    end
    issue.with_key(issue.open)
end, {
    nargs = '?',
    complete = known_keys,
    desc = 'Read an issue in a buffer',
})

vim.api.nvim_create_user_command('JiraGoto', function(opts)
    local argument = vim.trim(opts.args)
    if argument ~= '' then
        return issue.open(argument:upper())
    end
    issue.find(issue.open)
end, {
    nargs = '?',
    complete = known_keys,
    desc = 'Open an issue by key, or search for one by words',
})

vim.api.nvim_create_user_command('JiraOpen', function(opts)
    local argument = vim.trim(opts.args)
    if argument ~= '' then
        return actions.open_in_browser(argument:upper())
    end
    issue.with_key(actions.open_in_browser)
end, {
    nargs = '?',
    complete = known_keys,
    desc = 'Open an issue in the browser',
})

vim.api.nvim_create_user_command('JiraStart', function(opts)
    local argument = vim.trim(opts.args)
    if argument ~= '' then
        return require('qss_nvim.jira.work').start(argument)
    end
    picker.issues({ on_confirm = function(key)
        require('qss_nvim.jira.work').start(key)
    end })
end, {
    nargs = '?',
    complete = known_keys,
    desc = 'Assign, move and branch to start working on an issue',
})

vim.api.nvim_create_user_command('JiraCreate', M.create, {
    desc = 'Create an issue',
})

vim.api.nvim_create_user_command('JiraLink', function()
    issue.with_key(require('qss_nvim.jira.links').pick)
end, {
    desc = 'Links of an issue: follow one, cut one, add one',
})

vim.api.nvim_create_user_command('JiraFields', function()
    issue.with_key(require('qss_nvim.jira.fields').pick)
end, {
    desc = 'Edit the custom fields of an issue',
})

vim.api.nvim_create_user_command('JiraLog', function()
    issue.with_key(require('qss_nvim.jira.tempo').log)
end, {
    desc = 'Log time in Tempo on an issue',
})

vim.api.nvim_create_user_command('JiraWeek', function()
    require('qss_nvim.jira.timesheet').open()
end, {
    desc = 'Your Tempo timesheet, drawn week by week',
})

vim.api.nvim_create_user_command('JiraWeekList', function()
    require('qss_nvim.jira.tempo').week()
end, {
    desc = 'Your Tempo worklogs of this week, as a list',
})

vim.api.nvim_create_user_command('JiraCacheClear', function()
    cache.invalidate_prefix('')
    notify('the cache is empty', vim.log.levels.INFO)
end, {
    desc = 'Forget every answer Jira gave',
})

return M
