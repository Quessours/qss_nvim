-- Tempo is a separate product with a separate API and a separate token. On Jira
-- Cloud its worklogs and the native Jira worklogs are two different stores, so
-- `jira issue worklog add` writes a record the timesheet never shows. Only this
-- module feeds the timesheet.
--
-- Version 4 of the API also replaced the issue key with the numeric issue id,
-- which is the one thing here that has to be looked up before anything is sent.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local cli = require('qss_nvim.jira.cli')
local http = require('qss_nvim.jira.http')

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- Your Tempo author id. It never changes, so it is remembered for good.
---@param callback fun(account_id: string)
function M.account(callback)
    local remembered = cache.get('tempo.account_id')
    if remembered then
        return callback(remembered)
    end

    http.jira_rest('/rest/api/3/myself', function(decoded)
        local found = decoded.accountId
        if not found then
            return notify('Jira did not return an account id', vim.log.levels.ERROR)
        end
        cache.set('tempo.account_id', found)
        callback(found)
    end)
end

--- The numeric id behind an issue key, which is what v4 takes.
---@param key string
---@param callback fun(issue_id: string)
local function issue_id(key, callback)
    local cache_key = ('tempo.issue_id.%s'):format(key)
    local remembered = cache.get(cache_key)
    if remembered then
        return callback(remembered)
    end

    cli.json({ 'issue', 'view', key }, function(issue)
        if not issue.id then
            return notify(('%s has no numeric id'):format(key), vim.log.levels.ERROR)
        end
        cache.set(cache_key, tostring(issue.id))
        callback(tostring(issue.id))
    end)
end

--- Seconds out of what a person types. A bare number counts as minutes.
---@param spent string
---@return integer?
local function to_seconds(spent)
    local text = spent:lower():gsub('%s+', '')
    if text == '' then
        return nil
    end

    local bare = text:match('^%d+$')
    if bare then
        return tonumber(bare) * 60
    end

    -- 1h30, the shape people type when they mean an hour and a half.
    local hours, minutes = text:match('^(%d+)h(%d+)$')
    if hours then
        return tonumber(hours) * 3600 + tonumber(minutes) * 60
    end

    local total = 0
    local matched = 0
    for amount, unit in text:gmatch('(%d+)([dhm])') do
        local scale = unit == 'd' and 28800 or unit == 'h' and 3600 or 60
        total = total + tonumber(amount) * scale
        matched = matched + #amount + 1
    end

    if matched ~= #text or total == 0 then
        return nil
    end
    return total
end

---@param seconds integer
---@return string
function M.to_duration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours == 0 then
        return ('%dm'):format(minutes)
    end
    if minutes == 0 then
        return ('%dh'):format(hours)
    end
    return ('%dh%02dm'):format(hours, minutes)
end

--- The attributes this instance insists on, asked for one after another.
---@param callback fun(attributes: { key: string, value: string }[])
local function ask_attributes(callback)
    http.tempo('GET', '/work-attributes', nil, function(decoded)
        local required = vim.tbl_filter(function(attribute)
            return attribute.required
        end, decoded.results or {})

        local answers = {}
        local position = 0

        local function advance()
            position = position + 1
            local attribute = required[position]
            if not attribute then
                return callback(answers)
            end

            local choices = attribute.values or {}
            if #choices > 0 then
                local items = {}
                for index, choice in ipairs(choices) do
                    items[#items + 1] = { text = tostring(choice.value or choice), idx = index }
                end
                return Snacks.picker({
                    source = 'jira_tempo_attribute',
                    items = items,
                    format = 'text',
                    title = attribute.name,
                    layout = { preset = 'select' },
                    confirm = function(picker, item)
                        picker:close()
                        if item then
                            answers[#answers + 1] = { key = attribute.key, value = item.text }
                        end
                        advance()
                    end,
                })
            end

            Snacks.input({ prompt = ('%s: '):format(attribute.name) }, function(answer)
                if answer and vim.trim(answer) ~= '' then
                    answers[#answers + 1] = { key = attribute.key, value = vim.trim(answer) }
                end
                advance()
            end)
        end

        advance()
    end)
end

--- Log time on an issue.
---@param key string
---@param options { date: string?, on_done: fun()? }? a day picked elsewhere, and
---                what to do once the worklog landed
function M.log(key, options)
    Snacks.input({ prompt = ('Time on %s (1d 2h 30m, a bare number is minutes): '):format(key) },
        function(spent)
        local seconds = spent and to_seconds(spent)
        if not seconds then
            return notify('that is not a duration', vim.log.levels.WARN)
        end

        local today = options and options.date or os.date('%Y-%m-%d') --[[@as string]]
        Snacks.input({ prompt = ('Date for %s: '):format(key), default = today }, function(date)
            local start_date = date and vim.trim(date) or ''
            if not start_date:match('^%d%d%d%d%-%d%d%-%d%d$') then
                return notify('that is not a date of the form YYYY-MM-DD', vim.log.levels.WARN)
            end

            local now = os.date('%H:%M') --[[@as string]]
            Snacks.input({ prompt = ('Started at, on %s: '):format(key), default = now },
                function(started)
                local start_time = started and vim.trim(started) or ''
                local hours, minutes = start_time:match('^(%d%d?):(%d%d)$')
                if not hours then
                    return notify('that is not a time of the form HH:MM', vim.log.levels.WARN)
                end
                start_time = ('%02d:%s:00'):format(tonumber(hours), minutes)

                Snacks.input({ prompt = 'Description: ' }, function(description)
                    M.account(function(author)
                    issue_id(key, function(numeric_id)
                        ask_attributes(function(attributes)
                            local body = {
                                issueId = tonumber(numeric_id),
                                timeSpentSeconds = seconds,
                                startDate = start_date,
                                startTime = start_time,
                                description = description and vim.trim(description) or '',
                                authorAccountId = author,
                                attributes = attributes,
                            }
                            http.tempo('POST', '/worklogs', body, function()
                                notify(('logged %s on %s at %s'):format(
                                    M.to_duration(seconds), key, start_time:sub(1, 5)),
                                    vim.log.levels.INFO)
                                require('qss_nvim.jira.timesheet').refresh()
                                if options and options.on_done then
                                    options.on_done()
                                end
                            end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end

---@param text string
---@return string
local function percent_encode(text)
    return (text:gsub('[^%w%-%.%_%~]', function(character)
        return ('%%%02X'):format(character:byte())
    end))
end

--- A worklog names its issue by numeric id and nothing else, so the keys come
--- back from one Jira search rather than one lookup per row. Each pair is kept,
--- because an id never starts pointing at another issue.
---@param ids string[]
---@param callback fun(keys: table<string, string>)
function M.resolve_keys(ids, callback)
    local keys = {}
    local unknown = {}

    for _, id in ipairs(ids) do
        local remembered = cache.get(('tempo.issue_key.%s'):format(id))
        if remembered then
            keys[id] = remembered
        else
            unknown[#unknown + 1] = id
        end
    end

    if #unknown == 0 then
        return callback(keys)
    end

    local jql = ('id in (%s)'):format(table.concat(unknown, ','))
    local path = ('/rest/api/3/search/jql?jql=%s&fields=key&maxResults=100'):format(percent_encode(jql))

    http.jira_rest(path, function(decoded)
        for _, issue in ipairs(decoded.issues or {}) do
            local id = tostring(issue.id)
            keys[id] = issue.key
            cache.set(('tempo.issue_key.%s'):format(id), issue.key)
        end
        callback(keys)
    end)
end

--- Monday and Sunday of the week we are in.
---@return string from, string to
function M.week_bounds()
    local now = os.time()
    local weekday = tonumber(os.date('%w', now)) or 0
    local monday = now - ((weekday + 6) % 7) * 86400
    local sunday = monday + 6 * 86400
    return os.date('%Y-%m-%d', monday) --[[@as string]], os.date('%Y-%m-%d', sunday) --[[@as string]]
end

--- Every worklog of yours between two dates, with the issue keys resolved.
---@param from string
---@param to string
---@param callback fun(worklogs: table[], keys: table<string, string>)
function M.between(from, to, callback)
    M.account(function(author)
        local path = ('/worklogs/user/%s?from=%s&to=%s&limit=1000'):format(author, from, to)

        http.tempo('GET', path, nil, function(decoded)
            local worklogs = decoded.results or {}

            local ids = {}
            local seen = {}
            for _, worklog in ipairs(worklogs) do
                local id = worklog.issue and tostring(worklog.issue.id) or nil
                if id and not seen[id] then
                    seen[id] = true
                    ids[#ids + 1] = id
                end
            end

            M.resolve_keys(ids, function(keys)
                callback(worklogs, keys)
            end)
        end)
    end)
end

--- What each day of a range asks for, as Tempo knows it: the working pattern,
--- the public holidays and the non-working days. Reading it beats counting
--- weekends, which is the only thing a calendar can work out on its own and
--- gets a holiday wrong every time.
---@param from string
---@param to string
---@param callback fun(schedule: table<string, { required: integer, kind: string }>)
function M.schedule(from, to, callback)
    M.account(function(author)
        local cache_key = ('tempo.schedule.%s.%s'):format(from, to)
        local remembered = cache.get(cache_key)
        if remembered then
            return callback(remembered)
        end

        local path = ('/user-schedule/%s?from=%s&to=%s'):format(author, from, to)
        http.tempo('GET', path, nil, function(decoded)
            local schedule = {}
            for _, day in ipairs(decoded.results or {}) do
                schedule[day.date] = {
                    required = day.requiredSeconds or 0,
                    kind = day.type or 'WORKING_DAY',
                }
            end
            -- A week in the past never changes; a week ahead rarely does.
            cache.set(cache_key, schedule, 86400)
            callback(schedule)
        end)
    end)
end

--- Remove one worklog.
---@param worklog_id integer|string
---@param callback fun()
function M.remove(worklog_id, callback)
    http.tempo('DELETE', ('/worklogs/%s'):format(worklog_id), nil, callback)
end

--- The rows of one range, and the delete behind <CR>.
---@param from string
---@param to string
---@param worklogs table[]
---@param keys table<string, string> numeric issue id to issue key
local function show_worklogs(from, to, worklogs, keys)
    local total = 0
    local items = {}

    for index, worklog in ipairs(worklogs) do
        local seconds = worklog.timeSpentSeconds or 0
        total = total + seconds
        local id = worklog.issue and tostring(worklog.issue.id) or ''
        items[#items + 1] = {
            text = ('%s  %-8s %-12s %s'):format(worklog.startDate, M.to_duration(seconds),
                keys[id] or id, worklog.description or ''),
            worklog_id = worklog.tempoWorklogId,
            idx = index,
        }
    end

    Snacks.picker({
        source = 'jira_worklogs',
        items = items,
        format = 'text',
        title = ('Tempo %s to %s, %s logged'):format(from, to, M.to_duration(total)),
        confirm = function(picker, item)
            picker:close()
            if not item then
                return
            end
            local answer = vim.fn.confirm(('Delete this worklog?\n%s'):format(item.text), '&Yes\n&No', 2)
            if answer ~= 1 then
                return
            end
            http.tempo('DELETE', ('/worklogs/%s'):format(item.worklog_id), nil, function()
                notify('worklog deleted', vim.log.levels.INFO)
            end)
        end,
    })
end

--- Your worklogs of this week, with <CR> to delete one.
function M.week()
    local from, to = M.week_bounds()

    M.account(function(author)
        local path = ('/worklogs/user/%s?from=%s&to=%s&limit=200'):format(author, from, to)

        http.tempo('GET', path, nil, function(decoded)
            local worklogs = decoded.results or {}
            if #worklogs == 0 then
                return notify(('nothing logged between %s and %s'):format(from, to), vim.log.levels.INFO)
            end

            local ids = {}
            local seen = {}
            for _, worklog in ipairs(worklogs) do
                local id = worklog.issue and tostring(worklog.issue.id) or nil
                if id and not seen[id] then
                    seen[id] = true
                    ids[#ids + 1] = id
                end
            end

            M.resolve_keys(ids, function(keys)
                show_worklogs(from, to, worklogs, keys)
            end)
        end)
    end)
end

return M
