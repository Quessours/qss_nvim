-- A feature module rather than a plugin, in the shape of qt-class and cpp-impl:
-- required once from the root init.lua, registering its commands as it loads.
--
-- Picking the type of a new issue lives here because it is the one flow that has
-- no issue key to start from. The form it opens is in create.lua.
local M = {}

local TITLE = 'Jira'

local actions = require('qss_nvim.jira.actions')
local cache = require('qss_nvim.jira.cache')
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

--- Create an issue: pick the type, then fill the form that type decides.
---
--- The type comes first because it decides which fields the issue has and which
--- of them Jira requires. The list is what createmeta says you can create, so a
--- type your account cannot open is never offered.
function M.create()
    local instance = config.instance()
    if not (instance and instance.project) then
        return notify('jira-cli names no project. Run jira init.', vim.log.levels.ERROR)
    end

    local create = require('qss_nvim.jira.create')

    create.issue_types(instance.project, function(types)
        local items = {}
        for index, kind in ipairs(types) do
            items[#items + 1] = { text = kind.name, type_id = kind.id, idx = index }
        end

        Snacks.picker({
            source = 'jira_issue_types',
            items = items,
            format = 'text',
            title = ('New issue in %s'):format(instance.project),
            layout = { preset = 'select' },
            confirm = function(chooser, chosen)
                chooser:close()
                if chosen then
                    create.open(chosen.type_id)
                end
            end,
        })
    end)
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
