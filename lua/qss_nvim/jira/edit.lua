-- Editing one field, in the shape that field actually takes.
--
-- Jira is asked what it will accept on this issue right now, through editmeta:
-- which fields, of which type, and for a list field which values. That beats
-- both guessing and the jira-cli route, which resolves a custom field by its
-- label and therefore lands on the wrong one whenever two fields share a name,
-- and which refuses several types outright. Writing by field id has neither
-- problem.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
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
---@field operations string[]

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
    http.jira_put(('/rest/api/3/issue/%s'):format(key), { fields = { [field.id] = value } }, function()
        M.landed(key)
        notify(('%s: %s changed'):format(key, field.name), vim.log.levels.INFO)
        if done then
            done()
        end
    end)
end

--- The label of an allowed value. An option carries `value`, a priority or a
--- version carries `name`.
---@param entry table
---@return string
local function label_of(entry)
    return tostring(entry.displayName or entry.value or entry.name or entry.id)
end

---@param key string
---@param field qss.jira.EditField
---@param current any
---@param multiple boolean
---@param callback fun(chosen: table[])
local function choose(key, field, current, multiple, callback)
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
            and ('%s of %s  (<Tab> to take several)'):format(field.name, key)
            or ('%s of %s'):format(field.name, key),
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
                callback(chosen)
            end
        end,
    })
end

---@param key string
---@param field qss.jira.EditField
---@param current any
---@param done fun()?
local function edit_user(key, field, current, done)
    http.jira_rest(('/rest/api/3/user/assignable/search?issueKey=%s&maxResults=100'):format(key),
        function(people)
            local items = { { text = '○ nobody', account_id = vim.NIL, idx = 1 } }
            for index, person in ipairs(people) do
                local held = type(current) == 'table' and current.accountId == person.accountId
                items[#items + 1] = {
                    text = ('%s %s'):format(held and '●' or '○', person.displayName),
                    account_id = person.accountId,
                    idx = index + 1,
                }
            end

            Snacks.picker({
                source = 'jira_users',
                items = items,
                format = 'text',
                title = ('%s of %s'):format(field.name, key),
                layout = { preset = 'select' },
                confirm = function(picker, item)
                    picker:close()
                    if item then
                        write(key, field, item.account_id == vim.NIL and vim.NIL
                            or { accountId = item.account_id }, done)
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

---@param field qss.jira.EditField
---@return boolean
local function is_rich_text(field)
    if field.id == 'description' or field.id == 'environment' then
        return true
    end
    return field.custom ~= nil and RICH_TEXT[field.custom] == true
end

--- A rich text field, edited in a markdown buffer and written back as an
--- Atlassian document, the same way the description is.
---@param key string
---@param field qss.jira.EditField
---@param current any
---@param done fun()?
local function edit_rich_text(key, field, current, done)
    local adf = require('qss_nvim.jira.adf')
    local faithful, lost = adf.round_trips(current)

    if not faithful then
        return notify(('%s of %s does not survive a trip through markdown (%s). Edit it in the browser.')
            :format(field.name, key, lost and lost.type or 'unknown block'), vim.log.levels.WARN)
    end

    local lines, kept = adf.to_markdown(current)

    require('qss_nvim.jira.actions').compose({
        title = ('%s of %s'):format(field.name, key),
        initial = lines,
        on_submit = function(text)
            if text == vim.trim(table.concat(lines, '\n')) then
                return notify(('%s is unchanged'):format(field.name), vim.log.levels.INFO)
            end
            write(key, field, adf.to_adf(vim.split(text, '\n', { plain = true }), kept), done)
        end,
    })
end

--- Edit one field of one issue.
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

    if is_rich_text(field) then
        return edit_rich_text(key, field, current, done)
    end

    -- Original and remaining estimate are one field to Jira, so they are asked
    -- for together rather than one overwriting the other.
    if field.id == 'timetracking' then
        local held = type(current) == 'table' and current or {}
        return Snacks.input({ prompt = ('Original estimate of %s (2d 4h): '):format(key),
            default = held.originalEstimate or '' }, function(original)
            if original == nil then
                return
            end
            Snacks.input({ prompt = ('Remaining estimate of %s (2d 4h): '):format(key),
                default = held.remainingEstimate or vim.trim(original) }, function(remaining)
                if remaining == nil then
                    return
                end
                write(key, field, {
                    originalEstimate = vim.trim(original),
                    remainingEstimate = vim.trim(remaining),
                }, done)
            end)
        end)
    end

    if field.type == 'option' or field.type == 'priority' or field.type == 'version' then
        return choose(key, field, current, false, function(chosen)
            write(key, field, { id = tostring(chosen[1].id) }, done)
        end)
    end

    if field.type == 'user' then
        return edit_user(key, field, current, done)
    end

    if field.type == 'array' and field.allowed then
        return choose(key, field, current, true, function(chosen)
            local value = {}
            for _, entry in ipairs(chosen) do
                value[#value + 1] = { id = tostring(entry.id) }
            end
            write(key, field, value, done)
        end)
    end

    if field.type == 'array' and field.items == 'string' then
        return Snacks.input({ prompt = ('%s of %s (comma separated): '):format(field.name, key),
            default = as_text(field, current) }, function(answer)
            if answer == nil then
                return
            end
            write(key, field, split_list(answer), done)
        end)
    end

    if field.type == 'string' or field.type == 'date' or field.type == 'datetime' then
        local hint = field.type == 'date' and ' (YYYY-MM-DD)' or ''
        return Snacks.input({ prompt = ('%s of %s%s: '):format(field.name, key, hint),
            default = as_text(field, current) }, function(answer)
            if answer == nil then
                return
            end
            local text = vim.trim(answer)
            write(key, field, text ~= '' and text or vim.NIL, done)
        end)
    end

    if field.type == 'number' then
        return Snacks.input({ prompt = ('%s of %s: '):format(field.name, key),
            default = as_text(field, current) }, function(answer)
            if answer == nil then
                return
            end
            local text = vim.trim(answer)
            if text == '' then
                return write(key, field, vim.NIL, done)
            end
            local number = tonumber(text)
            if not number then
                return notify(('%s takes a number'):format(field.name), vim.log.levels.WARN)
            end
            write(key, field, number, done)
        end)
    end

    notify(('%s is a %s field, which this editor can not write. Use the browser.')
        :format(field.name, field.items and ('%s of %s'):format(field.type, field.items) or field.type),
        vim.log.levels.WARN)
end

return M
