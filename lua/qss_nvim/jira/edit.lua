-- Editing one field, in the shape that field actually takes.
--
-- Jira is asked what it will accept on this issue right now, through editmeta:
-- which fields, of which type, and for a list field which values. That beats
-- both guessing and the jira-cli route, which resolves a custom field by its
-- label and therefore lands on the wrong one whenever two fields share a name,
-- and which refuses several types outright. Writing by field id has neither
-- problem.
--
-- Asking for a value and writing it are two things. `M.ask` runs the prompt a
-- field takes and hands the value back; `M.field` writes what it hands back.
-- The create form collects a whole issue before anything is sent, so it calls
-- the first and never the second.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local cli = require('qss_nvim.jira.cli')
local http = require('qss_nvim.jira.http')

-- Short, because a workflow can change what is editable as the status moves.
local META_TTL = 300

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@class qss.jira.EditField
---@field id string the field id, for example customfield_11912 or summary
---@field name string
---@field type string the schema type
---@field items string? the element type of an array
---@field allowed table[]? the values Jira will take
---@field custom string? the custom field type, which tells a one-line text field from a rich one
---@field required boolean? Jira refuses the issue without it
---@field operations string[]

--- Where a value is going: an issue that already exists, or the project an
--- issue is about to be created in. A prompt needs both the name it shows and,
--- for a user field, the scope of the search behind it.
---@class qss.jira.Target
---@field key string? the issue, when there is one
---@field project string? the project, when the issue does not exist yet
---@field label string what a prompt calls it

--- The fields Jira will accept on this issue right now.
---@param key string
---@param callback fun(fields: qss.jira.EditField[])
function M.editable(key, callback)
    local cache_key = ('editmeta.%s'):format(key)
    local remembered = cache.get(cache_key)
    if remembered then
        return callback(remembered)
    end

    http.jira_rest(('/rest/api/3/issue/%s/editmeta'):format(key), function(decoded)
        local fields = {}
        for id, described in pairs(decoded.fields or {}) do
            local schema = described.schema or {}
            fields[#fields + 1] = {
                id = id,
                name = described.name or id,
                type = schema.type or 'any',
                items = schema.items,
                custom = schema.custom,
                allowed = described.allowedValues,
                operations = described.operations or {},
            }
        end

        table.sort(fields, function(left, right)
            return left.name < right.name
        end)
        cache.set(cache_key, fields, META_TTL)
        callback(fields)
    end)
end

--- What happens after any change to an issue, wherever it was made: the lists
--- that now show an old value are dropped, and every view of that issue on
--- screen is redrawn. One function, so no caller has to remember to do it.
---@param key string
function M.landed(key)
    cache.invalidate(('editmeta.%s'):format(key))
    cache.invalidate_prefix('issues.')
    require('qss_nvim.jira.issue').refresh(key)
    require('qss_nvim.jira.board').refresh()
end

---@param key string
---@param field qss.jira.EditField
---@param value any what to send, or vim.NIL to clear the field
---@param done fun()?
local function write(key, field, value, done)
    local function landed()
        M.landed(key)
        notify(('%s: %s changed'):format(key, field.name), vim.log.levels.INFO)
        if done then
            done()
        end
    end

    if M.is_sprint(field) then
        return M.write_sprint(key, value, landed)
    end

    http.jira_put(('/rest/api/3/issue/%s'):format(key), { fields = { [field.id] = value } }, landed)
end

--- The label of an allowed value. An option carries `value`, a priority or a
--- version carries `name`.
---@param entry table
---@return string
local function label_of(entry)
    return tostring(entry.displayName or entry.value or entry.name or entry.id)
end

---@param target qss.jira.Target
---@param field qss.jira.EditField
---@param current any
---@param multiple boolean
---@param callback fun(chosen: table[], text: string)
local function choose(target, field, current, multiple, callback)
    local held = {}
    if multiple then
        for _, entry in ipairs(type(current) == 'table' and current or {}) do
            held[tostring(entry.id)] = true
        end
    elseif type(current) == 'table' and current.id then
        held[tostring(current.id)] = true
    end

    local items = {}
    for index, entry in ipairs(field.allowed or {}) do
        items[#items + 1] = {
            text = ('%s %s'):format(held[tostring(entry.id)] and '●' or '○', label_of(entry)),
            entry = entry,
            idx = index,
        }
    end

    if #items == 0 then
        return notify(('%s has no value to choose from'):format(field.name), vim.log.levels.WARN)
    end

    Snacks.picker({
        source = 'jira_field_values',
        items = items,
        format = 'text',
        title = multiple
            and ('%s of %s  (<Tab> to take several)'):format(field.name, target.label)
            or ('%s of %s'):format(field.name, target.label),
        layout = { preset = 'select' },
        confirm = function(picker, item)
            local selected = multiple and picker:selected({ fallback = true }) or { item }
            picker:close()

            local chosen = {}
            for _, entry in ipairs(selected) do
                if entry and entry.entry then
                    chosen[#chosen + 1] = entry.entry
                end
            end
            if #chosen > 0 then
                local labels = {}
                for _, entry in ipairs(chosen) do
                    labels[#labels + 1] = label_of(entry)
                end
                callback(chosen, table.concat(labels, ', '))
            end
        end,
    })
end

--- Who Jira will let this field name. The search is scoped to the issue when
--- there is one, and to the project when the issue is still being written.
---@param target qss.jira.Target
---@return string?
local function assignable_path(target)
    if target.key then
        return ('/rest/api/3/user/assignable/search?issueKey=%s&maxResults=100'):format(target.key)
    end
    if target.project then
        return ('/rest/api/3/user/assignable/search?project=%s&maxResults=100'):format(target.project)
    end
    return nil
end

---@param target qss.jira.Target
---@param field qss.jira.EditField
---@param current any
---@param callback fun(value: any, text: string)
local function ask_user(target, field, current, callback)
    local path = assignable_path(target)
    if not path then
        return notify(('%s needs an issue or a project to search in'):format(field.name), vim.log.levels.WARN)
    end

    http.jira_rest(path, function(people)
        local items = { { text = '○ nobody', account_id = vim.NIL, name = '', idx = 1 } }
        for index, person in ipairs(people) do
            local held = type(current) == 'table' and current.accountId == person.accountId
            items[#items + 1] = {
                text = ('%s %s'):format(held and '●' or '○', person.displayName),
                account_id = person.accountId,
                name = person.displayName,
                idx = index + 1,
            }
        end

        Snacks.picker({
            source = 'jira_users',
            items = items,
            format = 'text',
            title = ('%s of %s'):format(field.name, target.label),
            layout = { preset = 'select' },
            confirm = function(picker, item)
                picker:close()
                if item then
                    callback(item.account_id == vim.NIL and vim.NIL or { accountId = item.account_id },
                        item.name)
                end
            end,
        })
    end)
end

---@param field qss.jira.EditField
---@param current any
---@return string
local function as_text(field, current)
    if current == nil or current == vim.NIL then
        return ''
    end
    if field.type == 'array' then
        local parts = {}
        for _, entry in ipairs(type(current) == 'table' and current or {}) do
            parts[#parts + 1] = type(entry) == 'table' and label_of(entry) or tostring(entry)
        end
        return table.concat(parts, ', ')
    end
    if type(current) == 'table' then
        return label_of(current)
    end
    return tostring(current)
end

---@param answer string
---@return string[]
local function split_list(answer)
    local parts = {}
    for _, piece in ipairs(vim.split(answer, ',', { plain = true })) do
        local trimmed = vim.trim(piece)
        if trimmed ~= '' then
            parts[#parts + 1] = trimmed
        end
    end
    return parts
end

-- Jira calls both a one-line text box and a whole rich-text area a `string`.
-- Only the custom field type tells them apart, and the difference matters: the
-- rich one holds an Atlassian document, which a one-line prompt turns into the
-- word "nil".
local RICH_TEXT = {
    ['com.atlassian.jira.plugin.system.customfieldtypes:textarea'] = true,
    ['com.atlassian.jira.plugin.system.customfieldtypes:readonlyfield'] = true,
}

-- The epic an issue hangs under. Its schema type is `any`, so nothing but the
-- custom type says what it holds, and it holds an issue key.
local EPIC_LINK = 'com.pyxis.greenhopper.jira:gh-epic-link'

-- The sprints an issue has been through. Jira reports the field as an array of
-- opaque objects, so the custom type is again the only thing that names it.
local GH_SPRINT = 'com.pyxis.greenhopper.jira:gh-sprint'

--- Which sprint a row holds. It is the shape the sprint picker hands back, and
--- not a value Jira takes in a field.
---@class qss.jira.Sprint
---@field id string
---@field name string

--- Whether a field is the sprint of an issue. A sprint belongs to the board
--- rather than to the issue, so it is read as a field and written as a move.
---@param field qss.jira.EditField
---@return boolean
function M.is_sprint(field)
    return field.custom == GH_SPRINT
end

--- Move an issue into a sprint. A PUT of the field is refused on most boards,
--- and the agile endpoint behind `sprint add` is what the board itself calls.
---@param key string
---@param sprint qss.jira.Sprint
---@param done fun()
function M.write_sprint(key, sprint, done)
    cli.write({ 'sprint', 'add', sprint.id, key }, '', done)
end

---@param field qss.jira.EditField
---@return boolean
local function is_rich_text(field)
    if field.id == 'description' or field.id == 'environment' then
        return true
    end
    return field.custom ~= nil and RICH_TEXT[field.custom] == true
end

--- What a whole document reads as on one row: its first line with something on
--- it, which is the heading or the opening sentence.
---@param lines string[]
---@return string
local function first_line(lines)
    for _, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= '' then
            return trimmed:sub(1, 60)
        end
    end
    return ''
end

--- A rich text field, edited in a markdown buffer and handed back as an
--- Atlassian document, the same way the description is.
---@param target qss.jira.Target
---@param field qss.jira.EditField
---@param current any
---@param callback fun(value: any, text: string)
local function ask_rich_text(target, field, current, callback)
    local adf = require('qss_nvim.jira.adf')
    local faithful, lost = adf.round_trips(current)

    if not faithful then
        return notify(('%s of %s does not survive a trip through markdown (%s). Edit it in the browser.')
            :format(field.name, target.label, lost and lost.type or 'unknown block'), vim.log.levels.WARN)
    end

    local lines, kept = adf.to_markdown(current)

    require('qss_nvim.jira.actions').compose({
        title = ('%s of %s'):format(field.name, target.label),
        initial = lines,
        on_submit = function(text)
            if text == vim.trim(table.concat(lines, '\n')) then
                return notify(('%s is unchanged'):format(field.name), vim.log.levels.INFO)
            end
            local written = vim.split(text, '\n', { plain = true })
            callback(adf.to_adf(written, kept), first_line(written))
        end,
    })
end

--- Which prompt a field takes. One answer, read by the prompt itself and by the
--- form that has to know whether a row can be filled at all. Two lists would
--- drift, and the form would offer a row that answers "use the browser".
---@param field qss.jira.EditField
---@return string? kind
local function kind_of(field)
    if is_rich_text(field) then
        return 'rich'
    end
    if field.custom == EPIC_LINK then
        return 'epic'
    end
    if M.is_sprint(field) then
        return 'sprint'
    end
    -- Original and remaining estimate are one field to Jira, so they are asked
    -- for together rather than one overwriting the other.
    if field.id == 'timetracking' then
        return 'timetracking'
    end
    if field.type == 'option' or field.type == 'priority' or field.type == 'version' then
        return 'option'
    end
    if field.type == 'user' then
        return 'user'
    end
    if field.type == 'array' and field.allowed then
        return 'options'
    end
    if field.type == 'array' and field.items == 'string' then
        return 'strings'
    end
    if field.type == 'string' or field.type == 'date' or field.type == 'datetime' then
        return 'text'
    end
    if field.type == 'number' then
        return 'number'
    end
    return nil
end

--- Whether this editor can write a field at all.
---@param field qss.jira.EditField
---@return boolean
function M.writable(field)
    return kind_of(field) ~= nil
end

--- Run the prompt a field takes and hand the value back. Nothing is written
--- here, so the same prompts serve an issue that exists and one that does not.
---@param target qss.jira.Target
---@param field qss.jira.EditField
---@param current any the value the field holds now, or nil on a new issue
---@param callback fun(value: any, text: string) never called when the prompt is dropped
function M.ask(target, field, current, callback)
    local kind = kind_of(field)

    if kind == 'rich' then
        return ask_rich_text(target, field, current, callback)
    end

    if kind == 'epic' then
        return require('qss_nvim.jira.picker').epics({
            on_confirm = function(epic)
                callback(epic, epic)
            end,
        })
    end

    if kind == 'sprint' then
        return require('qss_nvim.jira.picker').sprints(function(sprint)
            callback({ id = sprint.id, name = sprint.name }, sprint.name)
        end)
    end

    if kind == 'timetracking' then
        local held = type(current) == 'table' and current or {}
        return Snacks.input({ prompt = ('Original estimate of %s (2d 4h): '):format(target.label),
            default = held.originalEstimate or '' }, function(original)
            if original == nil then
                return
            end
            Snacks.input({ prompt = ('Remaining estimate of %s (2d 4h): '):format(target.label),
                default = held.remainingEstimate or vim.trim(original) }, function(remaining)
                if remaining == nil then
                    return
                end
                local estimates = {
                    originalEstimate = vim.trim(original),
                    remainingEstimate = vim.trim(remaining),
                }
                callback(estimates, ('original %s · remaining %s')
                    :format(estimates.originalEstimate, estimates.remainingEstimate))
            end)
        end)
    end

    if kind == 'option' then
        return choose(target, field, current, false, function(chosen, text)
            callback({ id = tostring(chosen[1].id) }, text)
        end)
    end

    if kind == 'user' then
        return ask_user(target, field, current, callback)
    end

    if kind == 'options' then
        return choose(target, field, current, true, function(chosen, text)
            local value = {}
            for _, entry in ipairs(chosen) do
                value[#value + 1] = { id = tostring(entry.id) }
            end
            callback(value, text)
        end)
    end

    if kind == 'strings' then
        return Snacks.input({ prompt = ('%s of %s (comma separated): '):format(field.name, target.label),
            default = as_text(field, current) }, function(answer)
            if answer == nil then
                return
            end
            local parts = split_list(answer)
            callback(parts, table.concat(parts, ', '))
        end)
    end

    if kind == 'text' then
        local hint = field.type == 'date' and ' (YYYY-MM-DD)' or ''
        return Snacks.input({ prompt = ('%s of %s%s: '):format(field.name, target.label, hint),
            default = as_text(field, current) }, function(answer)
            if answer == nil then
                return
            end
            local text = vim.trim(answer)
            callback(text ~= '' and text or vim.NIL, text)
        end)
    end

    if kind == 'number' then
        return Snacks.input({ prompt = ('%s of %s: '):format(field.name, target.label),
            default = as_text(field, current) }, function(answer)
            if answer == nil then
                return
            end
            local text = vim.trim(answer)
            if text == '' then
                return callback(vim.NIL, '')
            end
            local number = tonumber(text)
            if not number then
                return notify(('%s takes a number'):format(field.name), vim.log.levels.WARN)
            end
            callback(number, text)
        end)
    end

    notify(('%s is a %s field, which this editor can not write. Use the browser.')
        :format(field.name, field.items and ('%s of %s'):format(field.type, field.items) or field.type),
        vim.log.levels.WARN)
end

--- Edit one field of one issue: ask for the value, then write it.
---@param key string
---@param field qss.jira.EditField
---@param current any the value the issue holds now
---@param done fun()? runs once the change landed
function M.field(key, field, current, done)
    -- The description goes through jira-cli's own path, which already knows how
    -- to keep the blocks markdown cannot write.
    if field.id == 'description' then
        return require('qss_nvim.jira.actions').edit_description(key, done)
    end

    M.ask({ key = key, label = key }, field, current, function(value)
        write(key, field, value, done)
    end)
end

return M
