-- jira-cli already stores the server, the project, the board and the metadata of
-- every custom field. Reading its file instead of restating any of it here keeps
-- a single source of truth: `jira init` rewrites the file, and this module
-- follows without an edit.
local M = {}

local PATH = vim.fs.normalize('~/.config/.jira/.config.yml')

--- Options that belong to this module. jira-cli knows nothing about them.
M.options = {
    -- A `jira issue list` round trip costs about a second, which is too slow for
    -- a picker opened by reflex. <C-r> inside a picker drops the entry.
    cache_ttl = 5 * 60,
    branch_prefix = 'feature/',
    start_work_transition = 'In Progress',
    --- The steps of the start-work flow, in the order they run.
    start_work_steps = {
        assign = true,
        sprint = true,
        transition = true,
        branch = true,
        yank = true,
    },
    -- Prefill an empty commit message with the issue key of the branch.
    commit_prefix = true,
    --- Fields never worth a line, by the name Jira shows. An instance carries
    --- more than a hundred custom fields and most belong to another team.
    --- Matching is on the whole name and ignores case.
    hidden_fields = {
        'Projet Commerce',
        'Rank',
        'Development',
        'Atlassian Project',
        'Checklist Progress',
        'Checklist Progress %',
        'Checklist Text',
        'Checklist Text (view-only)',
        'Checklist Content YAML',
        'Checklist Completed',
        'Request Type',
        'Request language',
        'Request participants',
        'Organizations',
        'Satisfaction',
        'Satisfaction date',
        'Approvals',
        'Vulnerability',
        'Issue color',
    },
    tempo_url = 'https://api.tempo.io/4',
    -- What a full working day counts as, used only when Tempo will not say.
    -- Normally the real schedule is read from Tempo instead, which knows the
    -- working pattern and the public holidays and needs no guess here.
    daily_hours = 7,
}

---@class qss.jira.Field
---@field name string the label Jira shows, and the key the --custom flag takes
---@field key string the customfield_nnnnn identifier
---@field datatype string
---@field items string?
---@field writable boolean
---@field ambiguous boolean? another field carries the same name

---@class qss.jira.Instance
---@field server string
---@field login string
---@field installation string
---@field timezone string
---@field project string
---@field board string
---@field board_id string?
---@field custom_fields qss.jira.Field[]
---@field issue_types string[]

-- The datatypes jira-cli accepts behind --custom. It writes the others into the
-- config because Jira reports them, but refuses to send them: the API gives no
-- usable shape for a service-desk field, and `any` covers fields whose value is
-- an opaque object. `array` of `user` fails the same way, one level deeper.
local WRITABLE = {
    string = true,
    number = true,
    date = true,
    datetime = true,
    option = true,
    array = true,
}

---@param value string
---@return string
local function unquote(value)
    local trimmed = vim.trim(value)
    return (trimmed:gsub('^"(.*)"$', '%1'))
end

---@param field qss.jira.Field
---@return boolean
local function is_writable(field)
    local accepted = WRITABLE[field.datatype] == true
    local opaque_items = field.datatype == 'array' and field.items ~= 'string'
    return accepted and not opaque_items
end

--- The parts of jira-cli's config this module needs. The file has a known shape
--- and four spaces per level, so a scanner does the job a YAML library would.
---@return qss.jira.Instance?
local function read()
    local file = io.open(PATH, 'r')
    if not file then
        return nil
    end

    ---@type table<string, any>
    local instance = { custom_fields = {}, issue_types = {} }
    local section
    local list
    local entry

    for line in file:lines() do
        local top_key, top_value = line:match('^(%a[%w_]*):%s*(.*)$')
        if top_key then
            section, list, entry = top_key, nil, nil
            if top_value ~= '' then
                instance[top_key] = unquote(top_value)
            end
        elseif section == 'board' or section == 'project' then
            local key, value = line:match('^    (%a[%w_]*):%s*(.+)$')
            if key == 'name' or key == 'key' then
                instance[section] = unquote(value)
            elseif key == 'id' then
                instance[section .. '_id'] = unquote(value)
            end
        elseif section == 'issue' then
            if line:match('^%s+custom:%s*$') then
                list, entry = 'custom', nil
            elseif line:match('^%s+types:%s*$') then
                list, entry = 'types', nil
            elseif list == 'types' then
                -- An issue type opens on `- id:`, so its name is a plain nested
                -- key rather than the first key of the entry.
                local name = line:match('^%s+name:%s*(.+)$')
                if name then
                    instance.issue_types[#instance.issue_types + 1] = unquote(name)
                end
            elseif list == 'custom' then
                local name = line:match('^%s+%-%s*name:%s*(.+)$')
                if name then
                    entry = { name = unquote(name) }
                    instance.custom_fields[#instance.custom_fields + 1] = entry
                elseif entry then
                    local key = line:match('^%s+key:%s*(.+)$')
                    local datatype = line:match('^%s+datatype:%s*(.+)$')
                    local items = line:match('^%s+items:%s*(.+)$')
                    entry.key = key and unquote(key) or entry.key
                    entry.datatype = datatype and unquote(datatype) or entry.datatype
                    entry.items = items and unquote(items) or entry.items
                end
            end
        end
    end
    file:close()

    -- Two fields of the same name make --custom resolve to whichever key Jira
    -- returns first, which is the "cannot be set, or unknown" 400 in the
    -- jira-cli issue tracker. Mark both rather than pick one.
    local seen = {}
    for _, field in ipairs(instance.custom_fields) do
        field.datatype = field.datatype or 'any'
        field.writable = is_writable(field)
        local first = seen[field.name]
        if first then
            first.ambiguous, field.ambiguous = true, true
        else
            seen[field.name] = field
        end
    end
    return instance
end

local instance

--- The instance jira-cli talks to.
---@return qss.jira.Instance?
function M.instance()
    instance = instance or read()
    return instance
end

--- The custom fields --custom can actually write.
---@return qss.jira.Field[]
function M.writable_fields()
    local known = M.instance()
    if not known then
        return {}
    end
    return vim.tbl_filter(function(field)
        return field.writable
    end, known.custom_fields)
end

--- Whether a field is one you asked never to see.
---@param name string
---@return boolean
function M.is_hidden(name)
    local lowered = name:lower()
    for _, hidden in ipairs(M.options.hidden_fields) do
        if hidden:lower() == lowered then
            return true
        end
    end
    return false
end

--- The browser address of an issue.
---@param key string
---@return string?
function M.browse_url(key)
    local known = M.instance()
    if not (known and known.server) then
        return nil
    end
    return ('%s/browse/%s'):format(known.server, key)
end

return M
