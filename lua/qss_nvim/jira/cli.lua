-- Everything about issues goes through jira-cli rather than the REST API: it
-- already holds the credentials, the project and the custom field metadata, so
-- there is no second thing to configure and keep in step.
local M = {}

local TITLE = 'Jira'

-- jira-cli prints this and exits 0, so the exit code alone says nothing. The
-- usual cause is a JIRA_API_TOKEN that was set without -x in config.fish and
-- therefore never reaches a child process.
local TOKEN_MISSING = 'The tool needs a Jira API token'

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- Run jira-cli and hand its stdout back on the main loop. A failure is reported
--- once, here, and the callback receives nil.
---@param args string[]
---@param callback fun(stdout: string?)
---@param finally fun()? runs whether it worked or not, so a caller showing
---                     progress can stop showing it on either path
function M.run(args, callback, finally)
    local function done()
        if finally then
            finally()
        end
    end

    if vim.fn.executable('jira') ~= 1 then
        done()
        return notify('jira-cli is not on the PATH', vim.log.levels.ERROR)
    end

    local cmd = { 'jira' }
    vim.list_extend(cmd, args)

    vim.system(cmd, { text = true }, function(result)
        local stdout = result.stdout or ''

        vim.schedule(function()
            done()

            if stdout:find(TOKEN_MISSING, 1, true) then
                return notify('jira-cli has no API token. Export JIRA_API_TOKEN, then restart Neovim.',
                    vim.log.levels.ERROR)
            end
            if result.code ~= 0 then
                -- jira-cli prints its own errors on stdout, coloured, so the
                -- stream to read is not the one an exit code usually points at.
                local written = vim.trim(result.stderr or '') .. vim.trim(stdout)
                local reason = written:gsub('\27%[[%d;]*m', '')
                return notify(('jira %s failed: %s'):format(args[1] or '', reason ~= '' and reason or 'no output'),
                    vim.log.levels.ERROR)
            end
            callback(stdout)
        end)
    end)
end

--- Run a jira-cli query with --raw and decode the JSON it prints.
---@param args string[]
---@param callback fun(decoded: table)
function M.json(args, callback)
    local with_raw = vim.list_extend(vim.deepcopy(args), { '--raw' })

    M.run(with_raw, function(stdout)
        -- luanil, because Jira leaves an empty field as JSON null, which decodes
        -- to vim.NIL by default. vim.NIL is userdata, so it is truthy, and every
        -- `fields.assignee and fields.assignee.displayName` guard in this
        -- directory would pass and then index a userdata value.
        local ok, decoded = pcall(vim.json.decode, stdout,
            { luanil = { object = true, array = true } })
        if not (ok and type(decoded) == 'table') then
            return notify(('jira %s returned no usable JSON'):format(args[1] or ''), vim.log.levels.ERROR)
        end
        callback(decoded)
    end)
end

--- Run a jira-cli command that changes something, then say so.
---
--- --no-input is not added here: only `issue edit`, `issue comment add` and
--- `issue create` take it, and the others fail on an unknown flag. Each caller
--- passes it when its own command accepts it.
---@param args string[]
---@param message string what to report once it worked, empty when the caller reports
---@param callback fun()? runs after the change landed
function M.write(args, message, callback)
    local progress = require('qss_nvim.jira.progress')
    local token = progress.start('saving to Jira')

    M.run(args, function()
        if message ~= '' then
            notify(message, vim.log.levels.INFO)
        end
        if callback then
            callback()
        end
    end, function()
        progress.finish(token)
    end)
end

return M
