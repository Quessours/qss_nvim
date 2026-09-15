-- Two things jira-cli cannot do: reach Tempo, which is a separate product with
-- its own API and its own token, and report the account id that every Tempo call
-- needs. Both are plain HTTP, so curl does the work.
--
-- The credentials go to curl over stdin as a -K config rather than on the
-- command line, because an argv is readable by every process on the machine.
local M = {}

local TITLE = 'Jira'

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param name string
---@return string?
local function env(name)
    local value = vim.env[name]
    if value == nil or value == '' then
        return nil
    end
    return value
end

--- curl with the status code on its own last line, so a 4xx is told apart from a
--- body that happens to be empty.
---@param args string[]
---@param credentials string a curl -K config
---@param callback fun(status: integer, body: string)
local function request(args, credentials, callback, label)
    if vim.fn.executable('curl') ~= 1 then
        return notify('curl is not on the PATH', vim.log.levels.ERROR)
    end

    local cmd = { 'curl', '--silent', '--show-error', '--config', '-', '--write-out', '\n%{http_code}' }
    vim.list_extend(cmd, args)

    local progress = require('qss_nvim.jira.progress')
    local token = label and progress.start(label) or nil

    vim.system(cmd, { text = true, stdin = credentials }, function(result)
        local stdout = result.stdout or ''
        local body, status = stdout:match('^(.*)\n(%d+)$')

        vim.schedule(function()
            progress.finish(token)
            if not status then
                local reason = vim.trim(result.stderr or '')
                return notify(('the request failed: %s'):format(reason ~= '' and reason or 'no answer'),
                    vim.log.levels.ERROR)
            end
            callback(tonumber(status) or 0, body)
        end)
    end)
end

---@param status integer
---@param body string
---@param what string
---@return table?
local function decode(status, body, what)
    if status >= 400 then
        notify(('%s answered %d: %s'):format(what, status, vim.trim(body)), vim.log.levels.ERROR)
        return nil
    end
    if vim.trim(body) == '' then
        return {}
    end
    -- luanil for the same reason as in cli.lua: a null field must read as
    -- absent, not as a truthy vim.NIL.
    local ok, decoded = pcall(vim.json.decode, body,
        { luanil = { object = true, array = true } })
    if not ok then
        notify(('%s returned no usable JSON'):format(what), vim.log.levels.ERROR)
        return nil
    end
    return decoded
end

--- A call against the Jira REST API, with the same basic auth jira-cli uses.
---@param method string
---@param path string for example /rest/api/3/myself
---@param body table? sent as JSON
---@param callback fun(decoded: table)
local function jira_request(method, path, body, callback)
    local instance = require('qss_nvim.jira.config').instance()
    local api_token = env('JIRA_API_TOKEN')

    if not (instance and instance.server and instance.login) then
        return notify('jira-cli is not configured. Run jira init.', vim.log.levels.ERROR)
    end
    if not api_token then
        return notify('JIRA_API_TOKEN is not exported. Neovim inherits it from the shell.',
            vim.log.levels.ERROR)
    end

    local credentials = ('user = "%s:%s"\n'):format(instance.login, api_token)
    local args = { '--request', method, '--header', 'Accept: application/json' }

    if body then
        vim.list_extend(args, { '--header', 'Content-Type: application/json', '--data', vim.json.encode(body) })
    end
    args[#args + 1] = instance.server .. path

    -- A read is quick and silent; only a change is worth a sign.
    local label = method ~= 'GET' and 'saving to Jira' or nil

    request(args, credentials, function(status, answer)
        local decoded = decode(status, answer, 'Jira')
        if decoded then
            callback(decoded)
        end
    end, label)
end

--- Read from the Jira REST API.
---@param path string
---@param callback fun(decoded: table)
function M.jira_rest(path, callback)
    jira_request('GET', path, nil, callback)
end

--- Write to the Jira REST API.
---@param path string
---@param body table
---@param callback fun(decoded: table)
function M.jira_post(path, body, callback)
    jira_request('POST', path, body, callback)
end

--- Change fields of an existing issue.
---@param path string
---@param body table
---@param callback fun(decoded: table)
function M.jira_put(path, body, callback)
    jira_request('PUT', path, body, callback)
end

--- Remove something from Jira.
---@param path string
---@param callback fun(decoded: table)
function M.jira_delete(path, callback)
    jira_request('DELETE', path, nil, callback)
end

--- A call against the Tempo API. Tempo worklogs and native Jira worklogs are
--- separate stores on Cloud, and only this one feeds the timesheet.
---@param method string
---@param path string for example /worklogs
---@param body table? sent as JSON
---@param callback fun(decoded: table)
function M.tempo(method, path, body, callback)
    local api_token = env('TEMPO_API_TOKEN')
    if not api_token then
        return notify('TEMPO_API_TOKEN is not exported. Generate it in the Tempo API integration page.',
            vim.log.levels.ERROR)
    end

    local credentials = ('header = "Authorization: Bearer %s"\n'):format(api_token)
    local args = { '--request', method, '--header', 'Accept: application/json' }

    if body then
        vim.list_extend(args, { '--header', 'Content-Type: application/json', '--data', vim.json.encode(body) })
    end
    args[#args + 1] = require('qss_nvim.jira.config').options.tempo_url .. path

    local label = method ~= 'GET' and 'saving to Tempo' or nil

    request(args, credentials, function(status, answer)
        local decoded = decode(status, answer, 'Tempo')
        if decoded then
            callback(decoded)
        end
    end, label)
end

return M
