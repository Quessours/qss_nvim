-- Pick a field of an issue and edit it.
--
-- The list comes from editmeta, so it holds exactly what Jira will accept on
-- this issue right now: no field that cannot be written, no field that belongs
-- to another issue type, and no guessing from a label.
local M = {}

local TITLE = 'Jira'

local cli = require('qss_nvim.jira.cli')
local edit = require('qss_nvim.jira.edit')

-- Neither is a field: the status moves through a transition, and a sprint
-- through the board. Both are offered here because that is where a reader looks.
local STATUS = 'status'
local SPRINT = 'customfield_10005'

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- What Jira holds in a field, as one line.
---@param value any
---@return string
function M.render(value)
    if value == nil or value == vim.NIL then
        return ''
    end
    if type(value) ~= 'table' then
        return tostring(value)
    end
    if value.type == 'doc' then
        local lines = require('qss_nvim.jira.adf').to_markdown(value)
        return table.concat(lines, ' '):sub(1, 120)
    end
    -- A person is displayName, an option is value, a priority or a version is
    -- name. Jira uses all three and never two of them for the same thing.
    if value.displayName ~= nil then
        return tostring(value.displayName)
    end
    if value.value ~= nil then
        return tostring(value.value)
    end
    if value.name ~= nil then
        return tostring(value.name)
    end

    local parts = {}
    for _, entry in ipairs(value) do
        parts[#parts + 1] = M.render(entry)
    end
    return table.concat(parts, ', ')
end

---@param item snacks.picker.Item
---@return snacks.picker.Highlight[]
local function format_field(item)
    local shown = item.value ~= '' and item.value or '—'
    return {
        { ('%-28s'):format(item.field.name:sub(1, 28)), 'SnacksPickerLabel' },
        { ' ' },
        { ('%-12s'):format(item.field.type:sub(1, 12)), 'SnacksPickerComment' },
        { ' ' },
        { shown, item.value ~= '' and 'SnacksPickerDir' or 'SnacksPickerComment' },
    }
end

--- Every field of an issue, the ones carrying a value first.
---@param key string
---@param done fun()?
function M.pick(key, done)
    cli.json({ 'issue', 'view', key }, function(issue)
        local values = issue.fields or {}

        edit.editable(key, function(fields)
            local filled = {}
            local empty = {}

            for _, field in ipairs(fields) do
                if field.id ~= SPRINT then
                    local value = M.render(values[field.id])
                    local entry = {
                        text = ('%s %s %s'):format(field.name, field.type, value),
                        field = field,
                        value = value,
                        current = values[field.id],
                    }
                    local bucket = value ~= '' and filled or empty
                    bucket[#bucket + 1] = entry
                end
            end

            local status = values.status and values.status.name or ''
            local items = { {
                text = ('Status %s %s'):format(STATUS, status),
                field = { id = STATUS, name = 'Status', type = 'transition', operations = {} },
                value = status,
            } }
            vim.list_extend(items, filled)
            vim.list_extend(items, empty)
            for index, item in ipairs(items) do
                item.idx = index
            end

            Snacks.picker({
                source = 'jira_fields',
                items = items,
                format = format_field,
                title = ('Fields of %s'):format(key),
                confirm = function(picker, item)
                    picker:close()
                    if not item then
                        return
                    end
                    if item.field.id == STATUS then
                        return require('qss_nvim.jira.picker').transition(key, done)
                    end
                    edit.field(key, item.field, item.current, done)
                end,
            })
        end)
    end)
end

--- Report what a field can not do, for the caller that has no picker open.
---@param key string
function M.unavailable(key)
    notify(('nothing editable was found on %s'):format(key), vim.log.levels.WARN)
end

return M
