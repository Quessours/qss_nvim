-- The form that finishes an issue.
--
-- A create screen carries what Jira lets you set while the issue is being made,
-- which on most projects is a fraction of what the issue holds. The sprint, the
-- assignee and the estimates are on the edit screen and on no create screen, so
-- `order` in the config cannot reach them: the create form draws createmeta,
-- and createmeta does not report them.
--
-- So a second form opens on the issue that was just made, for the fields the
-- project names. It reads its rows from editmeta, which is the truth about what
-- this issue takes right now, and its values from the issue itself. Nothing is
-- carried over from the first form, so the address works on its own:
-- `:edit jira://after/LIS-2440` reopens it a day later.
local M = {}

local TITLE = 'Jira'

local cli = require('qss_nvim.jira.cli')
local config = require('qss_nvim.jira.config')
local edit = require('qss_nvim.jira.edit')
local fields_module = require('qss_nvim.jira.fields')
local form = require('qss_nvim.jira.form')
local http = require('qss_nvim.jira.http')
local utils = require('qss_nvim.utils')

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param key string
---@return string
function M.buffer_name(key)
    return ('jira://after/%s'):format(key)
end

--- The project a key belongs to, which is what names the configured fields.
---@param key string
---@return string?
local function project_of(key)
    return (key:match('^(%u[%u%d]*)%-%d+$'))
end

--- Whether a field of the issue reads as empty. Jira reports an untouched
--- object field as the literal "{}", which is a value to nobody.
---@param text string
---@return boolean
local function is_empty(text)
    return text == '' or text == '{}' or text == '[]'
end

--- The rows this form draws: the fields the project asks for, then every other
--- field the issue already carries. The second group is what you filled on the
--- create form, back on the screen and editable.
---
--- A configured field the edit screen refuses is named rather than drawn. A row
--- that cannot be filled is a dead end, and a dead end is worse than an absence.
---@param fields qss.jira.EditField[] what editmeta offers
---@param values table<string, any> what the issue holds
---@param options { after_create: string[], hidden: string[] }
---@return qss.jira.EditField[] rows, string[] refused
local function rows(fields, values, options)
    local wanted = {}
    for _, id in ipairs(options.after_create) do
        wanted[id] = true
    end

    local offered = {}
    local kept = {}
    for _, field in ipairs(fields) do
        offered[field.id] = true
        local carries = not is_empty(fields_module.render(values[field.id]))
        if wanted[field.id] or carries then
            kept[#kept + 1] = field
        end
    end

    local refused = {}
    for _, id in ipairs(options.after_create) do
        if not offered[id] then
            refused[#refused + 1] = id
        end
    end

    return form.ordered(kept, { order = options.after_create, hidden = options.hidden }), refused
end

--- What each row opens with: the value the issue holds for it.
---@param fields qss.jira.EditField[]
---@param values table<string, any>
---@return table<string, qss.jira.Held>
local function draft_of(fields, values)
    local draft = {}
    for _, field in ipairs(fields) do
        local text = fields_module.render(values[field.id])
        if not is_empty(text) then
            draft[field.id] = { value = values[field.id], text = text }
        end
    end
    return draft
end

--- Leave the form for the issue it belongs to. The issue exists either way, so
--- there is always somewhere to land.
---@param buffer integer
---@param key string
local function close(buffer, key)
    require('qss_nvim.jira.issue').open(key)
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
end

--- Send what you changed here, and nothing else. A row you left alone holds
--- what the issue already carries, and writing that back is a change which is
--- not one.
---@param drawn qss.jira.Form
---@param buffer integer
---@param key string
local function submit(drawn, buffer, key)
    local fields, sprint = form.payload(drawn, true)

    local function finish()
        edit.landed(key)
        close(buffer, key)
    end

    local function move()
        if sprint then
            return edit.write_sprint(key, sprint, finish)
        end
        finish()
    end

    if vim.tbl_isempty(fields) then
        if not sprint then
            return close(buffer, key)
        end
        return move()
    end

    http.jira_put(('/rest/api/3/issue/%s'):format(key), { fields = fields }, function()
        notify(('%s updated'):format(key), vim.log.levels.INFO)
        move()
    end)
end

--- Open the form for an issue. Opening it is `:edit jira://after/<key>` and
--- nothing more, so the address is what loads it, here and from the command
--- line alike.
---@param key string
function M.open(key)
    local window = utils.main_window()
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_set_current_win(window)
    end
    vim.cmd.edit(vim.fn.fnameescape(M.buffer_name(key)))
end

--- Fill a buffer nvim has just made for a `jira://after/<key>` name.
---@param buffer integer
---@param key string
function M.adopt(buffer, key)
    form.prepare(buffer, 'after')

    local project = project_of(key)
    local options = config.create_options(project)
    if #options.after_create == 0 then
        return form.write_lines(buffer, {
            ('%s names no field for this form.'):format(project or key),
            '',
            'Add one to create.<project>.after_create in lua/qss_nvim/jira/config.lua,',
            ('or open %s itself.'):format(key),
        })
    end

    form.write_lines(buffer, { ('Asking Jira what %s takes…'):format(key) })

    local issue
    local editable

    local function ready()
        if not (issue and editable) then
            return
        end

        local values = issue.fields or {}
        local drawn, refused = rows(editable, values, {
            after_create = options.after_create,
            hidden = options.hidden,
        })

        if #refused > 0 then
            notify(('the edit screen of %s takes none of %s'):format(key, table.concat(refused, ', ')),
                vim.log.levels.WARN)
        end

        form.adopt(buffer, {
            target = { key = key, label = key },
            fields = drawn,
            draft = draft_of(drawn, values),
            heading = {
                ('# %s  %s'):format(key, values.summary or ''),
                '  i or <CR> fills the field under the cursor · <C-s> saves · q leaves it',
                '',
            },
            on_submit = function(form_drawn, form_buffer)
                submit(form_drawn, form_buffer, key)
            end,
        })

        -- q closes any other Jira view. Here it has an issue to fall back to,
        -- and landing on the issue you just made beats landing on whatever was
        -- under the form.
        vim.keymap.set('n', 'q', function()
            close(buffer, key)
        end, { buffer = buffer, desc = 'Open the issue without saving' })
    end

    cli.json({ 'issue', 'view', key }, function(decoded)
        issue = decoded
        ready()
    end)

    edit.editable(key, function(fields)
        editable = fields
        ready()
    end)
end

return M
