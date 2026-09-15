-- :checkhealth qss_nvim.jira
--
-- Every failure this module can hit at run time shows up as one notification in
-- the middle of something else, which is a bad place to learn that a token was
-- never exported. The same checks, listed once, are easier to act on.
local M = {}

local config = require('qss_nvim.jira.config')

local health = vim.health

local function check_executables()
    health.start('Executables')

    if vim.fn.executable('jira') == 1 then
        local version = vim.fn.systemlist({ 'jira', 'version' })[1] or ''
        health.ok(('jira-cli is on the PATH: %s'):format(version))
    else
        health.error('jira-cli is not on the PATH',
            { 'Install it from https://github.com/ankitpokhrel/jira-cli, then run jira init.' })
    end

    if vim.fn.executable('curl') == 1 then
        health.ok('curl is on the PATH')
    else
        health.error('curl is not on the PATH', { 'Tempo and the account id lookup need it.' })
    end
end

local function check_tokens()
    health.start('Tokens')

    if vim.env.JIRA_API_TOKEN and vim.env.JIRA_API_TOKEN ~= '' then
        health.ok('JIRA_API_TOKEN reaches Neovim')
    else
        health.error('JIRA_API_TOKEN does not reach Neovim', {
            'In fish, `set NAME value` creates an unexported variable that no child process sees.',
            'Use `set -gx JIRA_API_TOKEN "..."` in config.fish, then open a new shell.',
        })
    end

    if vim.env.TEMPO_API_TOKEN and vim.env.TEMPO_API_TOKEN ~= '' then
        health.ok('TEMPO_API_TOKEN reaches Neovim')
    else
        health.warn('TEMPO_API_TOKEN does not reach Neovim', {
            'Only the worklog keys need it: <leader>jw and <leader>jW.',
            'Generate the token in the Tempo API integration page, then `set -gx TEMPO_API_TOKEN "..."`.',
        })
    end
end

local function check_instance()
    health.start('Instance')

    local instance = config.instance()
    if not instance then
        return health.error('jira-cli has no config file', { 'Run jira init.' })
    end

    health.ok(('%s, project %s, board %s'):format(
        instance.server or '?', instance.project or '?', instance.board or '?'))

    local writable = config.writable_fields()
    health.info(('%d custom fields, %d of them writable through --custom'):format(
        #instance.custom_fields, #writable))

    local ambiguous = vim.tbl_filter(function(field)
        return field.ambiguous
    end, instance.custom_fields)

    if #ambiguous > 0 then
        local names = {}
        for _, field in ipairs(ambiguous) do
            names[#names + 1] = ('%s (%s)'):format(field.name, field.key)
        end
        health.warn(('%d custom fields share a name with another one'):format(#ambiguous), {
            'jira-cli resolves --custom by name, so writing one of these can land on the wrong field.',
            table.concat(names, ', '),
        })
    end

    if #instance.issue_types > 0 then
        health.ok(('issue types: %s'):format(table.concat(instance.issue_types, ', ')))
    else
        health.warn('no issue type in the config', { 'Re-run jira init to refresh it.' })
    end
end

local function check_picker()
    health.start('Picker')

    if Snacks and Snacks.picker then
        health.ok('snacks.picker is loaded')
    else
        health.error('snacks.picker is not loaded', { 'Every entry point of this module is a picker.' })
    end
end

function M.check()
    check_executables()
    check_tokens()
    check_instance()
    check_picker()
end

return M
