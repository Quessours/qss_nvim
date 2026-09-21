-- A form of rows, one field to a row.
--
-- Two screens are drawn this way: the one that creates an issue, and the one
-- that finishes it once it exists. Both list fields, fill the one under the
-- cursor, hold what you filled, and send the lot on <C-s>. What each of them
-- asks Jira, and what each does with the answer, is all that differs. That is
-- what a spec carries, and the rest lives here.
local M = {}

local config = require('qss_nvim.jira.config')
local edit = require('qss_nvim.jira.edit')
local fields_module = require('qss_nvim.jira.fields')

local TITLE = 'Jira'

local namespace = vim.api.nvim_create_namespace('qss.jira.form')
local LABEL_WIDTH = 26

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- A value and the one line it reads as.
---@class qss.jira.Held
---@field value any what Jira takes, or vim.NIL for a row you emptied
---@field text string

--- What a screen brings to the form it draws.
---@class qss.jira.FormSpec
---@field target qss.jira.Target what the prompts call this issue
---@field fields qss.jira.EditField[] the rows, in the order they are drawn
---@field draft table<string, qss.jira.Held> the value each row starts from
---@field heading string[] the lines above the first row
---@field on_submit fun(drawn: qss.jira.Form, buffer: integer)

--- One form, for as long as its buffer lives. The draft is here rather than in
--- a buffer variable because a rich text value is a deep table, and a buffer
--- variable crosses into vimscript land and comes back changed. It is dropped
--- when the buffer is wiped, so it never outlives what it belongs to.
---@class qss.jira.Form : qss.jira.FormSpec
---@field owners table<integer, qss.jira.EditField> which line carries which field
---@field touched table<string, boolean> the rows you filled on this form
---@type table<integer, qss.jira.Form>
local forms = {}

--- The form a buffer carries, for the screen that has to read its draft.
---@param buffer integer
---@return qss.jira.Form?
function M.get(buffer)
    return forms[buffer]
end

--- The rows a form draws, in the order it draws them: the ones named in
--- `order` first, then the rest of what Jira requires, then the rest of what it
--- accepts.
---
--- A field no prompt can fill is dropped, unless Jira requires it. A row that
--- answers "use the browser" is a dead end, and a dead end is worse than an
--- absence. A required one stays, because the form has to say why it cannot
--- send the issue rather than hide the reason.
---@param fields qss.jira.EditField[]
---@param options { order: string[], hidden: string[] }
---@return qss.jira.EditField[]
function M.ordered(fields, options)
    local hidden = {}
    for _, id in ipairs(options.hidden) do
        hidden[id] = true
    end

    local rank = {}
    for index, id in ipairs(options.order) do
        rank[id] = index
    end

    local kept = vim.tbl_filter(function(field)
        if hidden[field.id] or config.is_hidden(field.name) then
            return false
        end
        return field.required or edit.writable(field)
    end, fields)

    table.sort(kept, function(left, right)
        local left_rank, right_rank = rank[left.id], rank[right.id]
        if left_rank and right_rank then
            return left_rank < right_rank
        end
        if left_rank or right_rank then
            return left_rank ~= nil
        end
        if left.required ~= right.required then
            return left.required == true
        end
        return left.name < right.name
    end)
    return kept
end

--- The value a default names, in the shape Jira takes. An option is written as
--- the label you read on the screen, so it is resolved against the values
--- createmeta reports rather than sent as it stands.
---@param field qss.jira.EditField
---@param wanted any
---@return any value, string text
local function resolve_default(field, wanted)
    if field.type == 'option' or field.type == 'priority' or field.type == 'version' then
        for _, entry in ipairs(field.allowed or {}) do
            if fields_module.render(entry) == wanted then
                return { id = tostring(entry.id) }, fields_module.render(entry)
            end
        end
        notify(('%s has no value called %s any more, so the form opens empty')
            :format(field.name, tostring(wanted)), vim.log.levels.WARN)
        return nil, ''
    end

    if field.type == 'array' and field.allowed then
        local names = type(wanted) == 'table' and wanted or { wanted }
        local value = {}
        local labels = {}
        for _, name in ipairs(names) do
            for _, entry in ipairs(field.allowed) do
                if fields_module.render(entry) == name then
                    value[#value + 1] = { id = tostring(entry.id) }
                    labels[#labels + 1] = name
                end
            end
        end
        if #value == 0 then
            return nil, ''
        end
        return value, table.concat(labels, ', ')
    end

    return wanted, tostring(wanted)
end

--- Fill the draft with what the project says a new issue starts from. The only
--- default that costs a request is `me` on a user field, which is your account
--- id, and that is read once and remembered for good.
---@param spec qss.jira.FormSpec
---@param defaults table<string, any>
---@param callback fun()
function M.apply_defaults(spec, defaults, callback)
    local by_id = {}
    for _, field in ipairs(spec.fields) do
        by_id[field.id] = field
    end

    local me
    for id, wanted in pairs(defaults) do
        local field = by_id[id]
        if field and field.type == 'user' and wanted == 'me' then
            me = field
        elseif field then
            local value, text = resolve_default(field, wanted)
            if value ~= nil then
                spec.draft[id] = { value = value, text = text }
            end
        end
    end

    if not me then
        return callback()
    end

    local login = (config.instance() or {}).login or 'you'
    require('qss_nvim.jira.tempo').account(function(account_id)
        spec.draft[me.id] = { value = { accountId = account_id }, text = login }
        callback()
    end)
end

--- What the draft sends. A sprint comes back on its own, because an issue is
--- moved into one through the board and never through a field.
---@param drawn qss.jira.Form
---@param only_touched boolean whether a row you left alone is sent too
---@return table<string, any> fields, qss.jira.Sprint? sprint
function M.payload(drawn, only_touched)
    local by_id = {}
    for _, field in ipairs(drawn.fields) do
        by_id[field.id] = field
    end

    local body = {}
    local sprint
    for id, held in pairs(drawn.draft) do
        local send
        if only_touched then
            -- A row you did not fill here holds what the issue already carries,
            -- and writing that back is a change which is not one.
            send = drawn.touched[id] == true
        else
            -- A new issue has nothing to clear, so an empty row is left out
            -- rather than sent as a null Jira can refuse.
            send = held.value ~= vim.NIL
        end

        local field = by_id[id]
        if send and field and edit.is_sprint(field) then
            sprint = held.value
        elseif send then
            body[id] = held.value
        end
    end
    return body, sprint
end

--- The fields Jira requires that the draft still leaves empty.
---@param drawn qss.jira.Form
---@return string[]
function M.missing(drawn)
    local names = {}
    for _, field in ipairs(drawn.fields) do
        local held = drawn.draft[field.id]
        if field.required and (held == nil or held.value == vim.NIL) then
            names[#names + 1] = field.name
        end
    end
    return names
end

--- Put lines in the buffer. It is unmodifiable the rest of the time, so that a
--- draft is changed by filling a field and never by typing over the drawing.
---@param buffer integer
---@param lines string[]
function M.write_lines(buffer, lines)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].modified = false
end

---@param drawn qss.jira.Form
---@return string[] lines, table<integer, qss.jira.EditField> owners
local function render(drawn)
    local lines = vim.deepcopy(drawn.heading)
    local owners = {}

    local required = 0
    for _, field in ipairs(drawn.fields) do
        local held = drawn.draft[field.id]
        local text = held and held.text or ''
        lines[#lines + 1] = ('%s %-' .. LABEL_WIDTH .. 's%s'):format(
            field.required and '*' or ' ',
            field.name:sub(1, LABEL_WIDTH - 1),
            text ~= '' and text or '—')
        owners[#lines] = field
        required = required + (field.required and 1 or 0)
    end

    if required > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('  * is one of the %d fields Jira requires here.'):format(required)
    end
    return lines, owners
end

---@param buffer integer
local function draw(buffer)
    local drawn = forms[buffer]
    if not (drawn and vim.api.nvim_buf_is_valid(buffer)) then
        return
    end

    local lines, owners = render(drawn)
    drawn.owners = owners

    local windows = vim.fn.win_findbuf(buffer)
    local cursors = {}
    for _, window in ipairs(windows) do
        cursors[window] = vim.api.nvim_win_get_cursor(window)
    end

    M.write_lines(buffer, lines)

    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    for line, field in pairs(owners) do
        vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, 0, {
            end_col = math.min(2 + LABEL_WIDTH, #lines[line]),
            hl_group = field.required and 'SnacksPickerDir' or 'SnacksPickerLabel',
        })
    end

    for window, position in pairs(cursors) do
        if vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_set_cursor(window, { math.min(position[1], #lines), position[2] })
        end
    end
end

---@param buffer integer
local function bind_keys(buffer)
    local function act()
        local drawn = forms[buffer]
        if not drawn then
            return
        end

        local line = vim.api.nvim_win_get_cursor(0)[1]
        local field = drawn.owners[line]
        if not field then
            return notify('this line is not a field. Move to one, or press <C-s> to send.',
                vim.log.levels.INFO)
        end

        local held = drawn.draft[field.id]
        edit.ask(drawn.target, field, held and held.value, function(value, text)
            if value == nil then
                drawn.draft[field.id] = nil
            else
                drawn.draft[field.id] = { value = value, text = text }
            end
            drawn.touched[field.id] = true
            draw(buffer)
        end)
    end

    vim.keymap.set('n', 'i', act, { buffer = buffer, desc = 'Fill the field under the cursor' })
    vim.keymap.set('n', '<CR>', act, { buffer = buffer, desc = 'Fill the field under the cursor' })
    vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
        local drawn = forms[buffer]
        if drawn then
            drawn.on_submit(drawn, buffer)
        end
    end, { buffer = buffer, desc = 'Send the form' })
end

--- The buffer options every form buffer takes. A draft has no reason to sit in
--- the buffer list once it is off the screen, and none of it is typed over.
---@param buffer integer
---@param view string what `vim.b.qss_jira_view` says this buffer is
function M.prepare(buffer, view)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'wipe'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
    vim.b[buffer].qss_jira_view = view
    vim.bo[buffer].filetype = 'jira'
end

--- Draw a form in a buffer and bind its keys.
---@param buffer integer
---@param spec qss.jira.FormSpec
function M.adopt(buffer, spec)
    ---@type qss.jira.Form
    local drawn = vim.tbl_extend('error', spec, { owners = {}, touched = {} })
    forms[buffer] = drawn

    vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buffer,
        once = true,
        desc = 'Drop the draft with the form it belongs to',
        callback = function()
            forms[buffer] = nil
        end,
    })

    draw(buffer)
    bind_keys(buffer)
end

return M
