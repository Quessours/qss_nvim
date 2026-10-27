-- The form for a new issue.
--
-- Creating an issue used to be three windows in a row: a type picker, then a
-- summary prompt, then a markdown buffer. One question at a time shows you
-- nothing of what the form asks, gives you no way back, and lets you leave
-- nothing for later. It also sent three fields, so a project that requires a
-- fourth refused every ticket.
--
-- So the whole issue is drawn at once, and nothing is sent until you say so.
-- Which fields exist, which of them Jira requires and which values they take
-- come from createmeta, which is to creating an issue what editmeta is to
-- editing one. Nothing about a project is guessed from a label here.
--
-- The rows are drawn by `form`, which the screen that finishes an issue uses as
-- well. What is left here is the createmeta half and the POST.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local config = require('qss_nvim.jira.config')
local edit = require('qss_nvim.jira.edit')
local fields_module = require('qss_nvim.jira.fields')
local form = require('qss_nvim.jira.form')
local http = require('qss_nvim.jira.http')
local template_module = require('qss_nvim.jira.template')
local utils = require('qss_nvim.utils')

-- The same five minutes editmeta is kept for. A create screen changes about as
-- often as an administrator edits it.
local META_TTL = 300

-- Neither is drawn: the header line already says the project and the type, and
-- neither can be changed without the form becoming another form.
local SKIPPED = { 'project', 'issuetype' }

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param type_id string
---@return string
function M.buffer_name(type_id)
    return ('jira://new/%s'):format(type_id)
end

--- The issue types you can actually create in a project, each with the id
--- createmeta and the create call both take. Sub-task types are left out: a
--- sub-task needs a parent, and the parent is where you make one.
---@param project string
---@param callback fun(types: { id: string, name: string }[])
function M.issue_types(project, callback)
    local cache_key = ('createmeta.types.%s'):format(project)
    local remembered = cache.get(cache_key)
    if remembered then
        return callback(remembered)
    end

    http.jira_rest(('/rest/api/3/issue/createmeta/%s/issuetypes?maxResults=200'):format(project),
        function(decoded)
            local types = {}
            for _, described in ipairs(decoded.issueTypes or decoded.values or {}) do
                if not described.subtask then
                    types[#types + 1] = { id = tostring(described.id), name = described.name }
                end
            end

            if #types == 0 then
                return notify(('%s offers no issue type to create'):format(project), vim.log.levels.ERROR)
            end
            cache.set(cache_key, types, META_TTL)
            callback(types)
        end)
end

--- The fields Jira will accept on a new issue of this type, in the shape the
--- field editor already speaks.
---@param project string
---@param type_id string
---@param callback fun(fields: qss.jira.EditField[])
function M.fields(project, type_id, callback)
    local cache_key = ('createmeta.fields.%s.%s'):format(project, type_id)
    local remembered = cache.get(cache_key)
    if remembered then
        return callback(remembered)
    end

    http.jira_rest(('/rest/api/3/issue/createmeta/%s/issuetypes/%s?maxResults=200'):format(project, type_id),
        function(decoded)
            local fields = {}
            for _, described in ipairs(decoded.fields or decoded.values or {}) do
                local schema = described.schema or {}
                fields[#fields + 1] = {
                    id = described.fieldId,
                    name = described.name or described.fieldId,
                    type = schema.type or 'any',
                    items = schema.items,
                    custom = schema.custom,
                    allowed = described.allowedValues,
                    required = described.required == true,
                    operations = described.operations or {},
                }
            end
            edit.add_time_tracking(fields)
            cache.set(cache_key, fields, META_TTL)
            callback(fields)
        end)
end

--- Where the new issue is handed over to. A project that configures a second
--- form gets it, and every other project gets the issue itself.
---@param project string
---@param key string
---@param buffer integer the form, which the next screen takes the window of
local function hand_over(project, key, buffer)
    if #config.create_options(project).after_create > 0 then
        require('qss_nvim.jira.after').open(key)
    else
        require('qss_nvim.jira.issue').open(key)
    end
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
end

--- Send the draft. The issue is built whole and posted once, so a form that
--- Jira refuses leaves nothing half-created behind.
---@param drawn qss.jira.Form
---@param buffer integer
---@param project string
---@param type_id string
---@param type_name string
---@param template qss.jira.Template? the form an automation writes over the description
local function submit(drawn, buffer, project, type_id, type_name, template)
    -- The form stays on screen until the sprint and the description are done,
    -- which takes up to half a minute with a template. A second <C-s> in that
    -- time made a second issue.
    if drawn.sent then
        local message = drawn.key and ('%s already exists. This form will not create it again.'):format(drawn.key)
            or 'the issue is on its way to Jira'
        return notify(message, vim.log.levels.WARN)
    end

    local empty = form.missing(drawn)
    if #empty > 0 then
        return notify(('%s still needs %s'):format(type_name, table.concat(empty, ', ')),
            vim.log.levels.WARN)
    end

    local fields, sprint = form.payload(drawn, false)
    fields.project = { key = project }
    fields.issuetype = { id = type_id }

    -- The form left as it opened is what the automation writes anyway, with
    -- the colours markdown cannot hold.
    local kept_description = template and drawn.touched.description and fields.description or nil
    if template and not kept_description then
        fields.description = nil
    end

    drawn.sent = true
    http.jira_post('/rest/api/3/issue', { fields = fields }, function(decoded)
        local key = decoded.key
        drawn.key = key
        cache.invalidate_prefix('issues.')

        if not key then
            -- Nothing to hand over to, and the form must not stay up to be sent
            -- a second time.
            if vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_buf_delete(buffer, { force = true })
            end
            return notify('the issue was created, but its key was not in the answer. Find it on the board.',
                vim.log.levels.WARN)
        end
        notify(('%s created'):format(key), vim.log.levels.INFO)

        -- The issue exists from here on, so a step after it that fails still
        -- closes the form: what failed is reported, and the issue is fixed in
        -- its own buffer.
        local function open_issue()
            hand_over(project, key, buffer)
        end
        local function finish()
            if sprint then
                return edit.write_sprint(key, sprint, open_issue, open_issue)
            end
            open_issue()
        end

        if template and kept_description then
            return template_module.restore(key, template, kept_description, finish)
        end
        finish()
    end, function()
        drawn.sent = false
    end)
end

--- Open the form for an issue type. Opening it is `:edit jira://new/<id>` and
--- nothing more, so the address is what loads it, here and from the command
--- line alike.
---@param type_id string
function M.open(type_id)
    local window = utils.main_window()
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_set_current_win(window)
    end
    vim.cmd.edit(vim.fn.fnameescape(M.buffer_name(type_id)))
end

--- Fill a buffer nvim has just made for a `jira://new/<type id>` name.
---@param buffer integer
---@param type_id string
function M.adopt(buffer, type_id)
    form.prepare(buffer, 'create')

    local instance = config.instance()
    local project = instance and instance.project
    if not project then
        return form.write_lines(buffer, { 'jira-cli names no project. Run jira init.' })
    end

    form.write_lines(buffer, { ('Asking %s what a new issue takes…'):format(project) })

    M.issue_types(project, function(types)
        local name
        for _, kind in ipairs(types) do
            if kind.id == type_id then
                name = kind.name
            end
        end
        if not name then
            return form.write_lines(buffer, {
                ('%s is not an issue type you can create in %s.'):format(type_id, project),
                '',
                'Run :JiraCreate to pick one from the list.',
            })
        end

        M.fields(project, type_id, function(fields)
            template_module.find(project, type_id, function(template)
                local options = config.create_options(project)
                local hidden = vim.list_extend(vim.deepcopy(SKIPPED), options.hidden)

                ---@type qss.jira.FormSpec
                local spec = {
                    target = { project = project, label = ('the new %s'):format(name) },
                    fields = form.ordered(fields, { order = options.order, hidden = hidden }),
                    draft = {},
                    heading = {
                        ('# New %s in %s'):format(name, project),
                        '  i or <CR> fills the field under the cursor · <C-s> creates · q drops',
                        '',
                    },
                    on_submit = function(drawn, drawn_buffer)
                        submit(drawn, drawn_buffer, project, type_id, name, template)
                    end,
                }

                if template then
                    local description = require('qss_nvim.jira.adf').to_adf(template.lines, {})
                    spec.draft.description = { value = description, text = fields_module.render(description) }
                end

                form.apply_defaults(spec, options.defaults, function()
                    form.adopt(buffer, spec)
                end)
            end)
        end)
    end)
end

return M
