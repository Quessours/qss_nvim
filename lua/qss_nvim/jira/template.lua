-- The description an automation writes on every new issue of a type.
--
-- On LIS, a rule rewrites the description of each new bug with a form of
-- headings and XXX placeholders, a few seconds after the issue exists, and
-- whatever the description held before is gone. createmeta knows nothing of it,
-- and the rule itself can only be read by an administrator.
--
-- This module is a workaround for that rule, and it has two halves.
--
-- The form comes from the changelog of the last issue of the type: the first
-- description change made by an app account is taken as the form. That text
-- follows the rule when the rule changes, but it is a guess from the history.
-- If the last issue was written over by another app, that text is the form.
-- The changelog is wiki markup, and its colours are lost on the way to markdown.
--
-- The description is written twice. The issue is created with it, the rule
-- writes over it, and this module polls the changelog every 1.5 s until the
-- rule has run, then sends the description again with a PUT. So the history of
-- every such issue shows two description changes after its creation, and the
-- PUT sends watchers an update notification. If the rule has not run after 30 s, the module stops waiting. If the
-- rule runs after that, the description is lost as before.
--
-- The real fix is on the rule: a condition "Description is empty" makes it
-- leave a written description alone. Once the rule has that condition, the
-- form half is still useful. The restore half then only waits 30 s for nothing
-- and warns, and can go.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local http = require('qss_nvim.jira.http')

-- As long as createmeta is kept. The rule changes about as often as a screen.
local TEMPLATE_TTL = 300
-- The rule runs two to five seconds after the issue exists.
local POLL_INTERVAL = 1500
local POLL_LIMIT = 30000

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@class qss.jira.Template
---@field lines string[] the form, as markdown
---@field author string the account id of the automation that writes it

--- A changelog is wiki markup, and the form uses only the plain part of it. A
--- colour has no markdown spelling, so its markers are dropped and the words
--- kept.
---@param wiki string
---@return string[]
function M.to_markdown(wiki)
    local lines = {}
    local blank = false
    for _, line in ipairs(vim.split(wiki:gsub('\r', ''), '\n', { plain = true })) do
        line = line:gsub('{color[^}]*}', '')
        line = line:gsub('^h(%d)%.%s+', function(level)
            return ('#'):rep(tonumber(level) or 1) .. ' '
        end)
        line = line:gsub('^%*+%s', '- ')
        line = line:gsub('%*([^*]+)%*', '**%1**')
        line = (' ' .. line):gsub('(%s)_([^_]+)_', '%1*%2*'):sub(2)

        -- The rule spaces its sections with two blank lines, markdown with one.
        local is_blank = vim.trim(line) == ''
        if not (is_blank and blank) then
            lines[#lines + 1] = is_blank and '' or line
        end
        blank = is_blank
    end
    while lines[#lines] == '' do
        lines[#lines] = nil
    end
    return lines
end

--- The description change an automation made on an issue, if it made one. An
--- automation is told from a person by its account type, never by its name.
---@param changelog table
---@param author string? only this account
---@return { author: string, wiki: string }?
local function automated_change(changelog, author)
    for _, change in ipairs(changelog.values or {}) do
        local by = change.author or {}
        if by.accountType == 'app' and (author == nil or by.accountId == author) then
            for _, item in ipairs(change.items or {}) do
                if item.fieldId == 'description' and item.toString then
                    return { author = by.accountId, wiki = item.toString }
                end
            end
        end
    end
    return nil
end

--- The form an automation writes on a new issue of this type, or nil when no
--- automation wrote one on the last issue of it.
---@param project string
---@param type_id string
---@param callback fun(template: qss.jira.Template?)
function M.find(project, type_id, callback)
    local cache_key = ('template.%s.%s'):format(project, type_id)
    local remembered = cache.get(cache_key)
    if remembered ~= nil then
        return callback(remembered ~= false and remembered or nil)
    end

    local function remember(template)
        cache.set(cache_key, template or false, TEMPLATE_TTL)
        callback(template)
    end

    local jql = ('project = %s AND issuetype = %s ORDER BY created DESC'):format(project, type_id)
    http.jira_rest(('/rest/api/3/search/jql?maxResults=1&fields=created&jql=%s'):format(vim.uri_encode(jql)),
        function(found)
            local latest = (found.issues or {})[1]
            if not latest then
                return remember(nil)
            end

            http.jira_rest(('/rest/api/3/issue/%s/changelog'):format(latest.key), function(changelog)
                local change = automated_change(changelog)
                if not change then
                    return remember(nil)
                end
                remember({ lines = M.to_markdown(change.wiki), author = change.author })
            end)
        end)
end

--- Let the automation write its form on a new issue, then put the description
--- back. Writing it back before the rule runs would only be written over.
---@param key string
---@param template qss.jira.Template
---@param description table the description as it was sent
---@param done fun() runs once it is over, whether the description came back or not
function M.restore(key, template, description, done)
    notify(('%s: waiting for the automation to pass, to put the description back'):format(key),
        vim.log.levels.INFO)

    local function give_up()
        notify(('%s: the description you wrote was not put back'):format(key), vim.log.levels.WARN)
        done()
    end

    local waited = 0
    local function poll()
        http.jira_rest(('/rest/api/3/issue/%s/changelog'):format(key), function(changelog)
            if automated_change(changelog, template.author) then
                return http.jira_put(('/rest/api/3/issue/%s'):format(key),
                    { fields = { description = description } }, done, give_up)
            end

            waited = waited + POLL_INTERVAL
            if waited >= POLL_LIMIT then
                notify(('%s: no automation rewrote the description in %d s, so it stays as sent')
                    :format(key, POLL_LIMIT / 1000), vim.log.levels.WARN)
                return done()
            end
            vim.defer_fn(poll, POLL_INTERVAL)
        end, give_up)
    end
    vim.defer_fn(poll, POLL_INTERVAL)
end

return M
