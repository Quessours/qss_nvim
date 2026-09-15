-- One menu behind <CR>, from the picker and from a jira:// buffer alike, so
-- there is a single place that knows what can be done to an issue.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local cli = require('qss_nvim.jira.cli')
local config = require('qss_nvim.jira.config')

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- The raw issue, for the actions that need to show the current value before
--- they change it.
---@param key string
---@param callback fun(issue: table)
local function fetch(key, callback)
    cli.json({ 'issue', 'view', key }, function(decoded)
        callback(decoded)
    end)
end

--- Report a change, drop the lists that now show the old value, and redraw
--- every view of the issue that is on screen.
---@param key string
---@param message string
local function changed(key, message)
    require('qss_nvim.jira.edit').landed(key)
    notify(message, vim.log.levels.INFO)
end

--- A floating markdown buffer for the fields that hold more than a line.
---@param options { title: string, initial: string[], on_submit: fun(text: string) }
function M.compose(options)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].filetype = 'markdown'
    vim.bo[buffer].bufhidden = 'wipe'
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, options.initial)
    require('qss_nvim.jira.completion').attach(buffer)

    local width = math.min(100, math.floor(vim.o.columns * 0.8))
    local height = math.min(24, math.floor(vim.o.lines * 0.6))

    local window = vim.api.nvim_open_win(buffer, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        border = 'rounded',
        title = ('%s  (<C-s> send · q drop · / for panels and lists)'):format(options.title),
        title_pos = 'center',
    })

    local function close()
        if vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_close(window, true)
        end
    end

    vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        close()
        local text = vim.trim(table.concat(lines, '\n'))
        if text == '' then
            return notify('nothing to send', vim.log.levels.WARN)
        end
        options.on_submit(text)
    end, { buffer = buffer, desc = 'Send to Jira' })

    vim.keymap.set('n', 'q', close, { buffer = buffer, desc = 'Drop the edit' })
end

---@param key string
function M.open_in_browser(key)
    local url = config.browse_url(key)
    if not url then
        return notify('the server is missing from the jira-cli config', vim.log.levels.ERROR)
    end
    vim.ui.open(url)
end

---@param key string
function M.yank_key(key)
    vim.fn.setreg('+', key)
    notify(('yanked %s'):format(key), vim.log.levels.INFO)
end

---@param key string
function M.yank_url(key)
    local url = config.browse_url(key)
    if not url then
        return notify('the server is missing from the jira-cli config', vim.log.levels.ERROR)
    end
    vim.fn.setreg('+', url)
    notify(('yanked %s'):format(url), vim.log.levels.INFO)
end

--- Assign the issue to anyone, or to nobody. The list is whoever Jira says can
--- be assigned on this issue, so it is never a guess at a name.
---@param key string
---@param done fun()?
function M.assign(key, done)
    local edit = require('qss_nvim.jira.edit')

    edit.editable(key, function(fields)
        local assignee
        for _, field in ipairs(fields) do
            if field.id == 'assignee' then
                assignee = field
            end
        end
        if not assignee then
            return notify(('%s does not take an assignee'):format(key), vim.log.levels.WARN)
        end

        cli.json({ 'issue', 'view', key }, function(issue)
            edit.field(key, assignee, (issue.fields or {}).assignee, done)
        end)
    end)
end

---@param key string
function M.assign_to_me(key)
    local instance = config.instance()
    if not (instance and instance.login) then
        return notify('the login is missing from the jira-cli config', vim.log.levels.ERROR)
    end
    cli.write({ 'issue', 'assign', key, instance.login }, '', function()
        changed(key, ('%s is yours'):format(key))
    end)
end

---@param key string
function M.unassign(key)
    cli.write({ 'issue', 'assign', key, 'x' }, '', function()
        changed(key, ('%s has no assignee'):format(key))
    end)
end

---@param key string
function M.add_comment(key)
    M.compose({
        title = ('Comment on %s'):format(key),
        initial = { '' },
        on_submit = function(text)
            cli.write({ 'issue', 'comment', 'add', key, text, '--no-input' }, '', function()
                changed(key, ('commented on %s'):format(key))
            end)
        end,
    })
end

--- Edit the description. The document goes back to Jira whole, through the API,
--- so a block markdown cannot express survives untouched: it sits in the buffer
--- as a comment line and is put back where that line ended up.
---@param key string
---@param done fun()?
function M.edit_description(key, done)
    fetch(key, function(issue)
        local adf = require('qss_nvim.jira.adf')
        local document = issue.fields and issue.fields.description
        local faithful, lost = adf.round_trips(document)

        if not faithful then
            return notify(('the description of %s does not survive a trip through markdown (%s). Edit it in the browser.')
                :format(key, lost and lost.type or 'unknown block'), vim.log.levels.WARN)
        end

        local lines, kept = adf.to_markdown(document)
        if #kept > 0 then
            notify(('%d block of %s stays as it is; its comment line holds the place')
                :format(#kept, key), vim.log.levels.INFO)
        end

        M.compose({
            title = ('Description of %s'):format(key),
            initial = lines,
            on_submit = function(text)
                -- Nothing typed, nothing sent.
                if text == vim.trim(table.concat(lines, '\n')) then
                    return notify('the description is unchanged', vim.log.levels.INFO)
                end
                local written = adf.to_adf(vim.split(text, '\n', { plain = true }), kept)
                require('qss_nvim.jira.http').jira_put(('/rest/api/3/issue/%s'):format(key),
                    { fields = { description = written } }, function()
                        changed(key, ('%s has a new description'):format(key))
                        if done then
                            done()
                        end
                    end)
            end,
        })
    end)
end

---@param key string
function M.edit_summary(key)
    fetch(key, function(issue)
        local current = issue.fields and issue.fields.summary or ''
        Snacks.input({ prompt = ('Summary of %s: '):format(key), default = current }, function(answer)
            local summary = answer and vim.trim(answer) or ''
            if summary == '' or summary == current then
                return
            end
            cli.write({ 'issue', 'edit', key, '--summary', summary, '--no-input' }, '', function()
                changed(key, ('%s has a new summary'):format(key))
            end)
        end)
    end)
end

---@param key string
function M.edit_labels(key)
    fetch(key, function(issue)
        local current = issue.fields and issue.fields.labels or {}
        local joined = table.concat(current, ', ')

        Snacks.input({ prompt = ('Labels of %s: '):format(key), default = joined }, function(answer)
            if answer == nil then
                return
            end

            local wanted = {}
            for _, label in ipairs(vim.split(answer, ',', { plain = true })) do
                local trimmed = vim.trim(label)
                if trimmed ~= '' then
                    wanted[trimmed] = true
                end
            end

            -- jira-cli takes one --label per change, and a leading dash removes.
            local args = { 'issue', 'edit', key }
            for _, label in ipairs(current) do
                if not wanted[label] then
                    vim.list_extend(args, { '--label', ('-%s'):format(label) })
                end
                wanted[label] = nil
            end
            for label in pairs(wanted) do
                vim.list_extend(args, { '--label', label })
            end

            if #args == 3 then
                return
            end
            args[#args + 1] = '--no-input'
            cli.write(args, '', function()
                changed(key, ('%s has new labels'):format(key))
            end)
        end)
    end)
end

---@param key string
function M.move_to_sprint(key)
    require('qss_nvim.jira.picker').sprints(function(sprint)
        cli.write({ 'sprint', 'add', sprint.id, key }, '', function()
            changed(key, ('%s is in %s'):format(key, sprint.name))
        end)
    end)
end

---@param key string
function M.add_to_epic(key)
    require('qss_nvim.jira.picker').epics({
        on_confirm = function(epic)
            cli.write({ 'epic', 'add', epic, key }, '', function()
                changed(key, ('%s is under %s'):format(key, epic))
            end)
        end,
    })
end

--- Whether a comment is yours, and therefore editable.
---@param comment table
---@return boolean
local function is_mine(comment)
    local account_id = cache.get('tempo.account_id')
    return account_id ~= nil and comment.author ~= nil and comment.author.accountId == account_id
end

--- Edit a comment already posted. Jira takes the document whole, the same way a
--- description is written.
---@param key string
---@param comment table
---@param done fun()?
function M.edit_comment(key, comment, done)
    local adf = require('qss_nvim.jira.adf')
    local faithful, lost = adf.round_trips(comment.body)

    if not faithful then
        return notify(('this comment does not survive a trip through markdown (%s). Edit it in the browser.')
            :format(lost and lost.type or 'unknown block'), vim.log.levels.WARN)
    end

    local lines, kept = adf.to_markdown(comment.body)

    M.compose({
        title = ('Comment on %s'):format(key),
        initial = lines,
        on_submit = function(text)
            if text == vim.trim(table.concat(lines, '\n')) then
                return notify('the comment is unchanged', vim.log.levels.INFO)
            end
            local body = adf.to_adf(vim.split(text, '\n', { plain = true }), kept)
            require('qss_nvim.jira.http').jira_put(
                ('/rest/api/3/issue/%s/comment/%s'):format(key, comment.id),
                { body = body }, function()
                    changed(key, ('the comment on %s is edited'):format(key))
                    if done then
                        done()
                    end
                end)
        end,
    })
end

--- Remove a comment, after asking.
---@param key string
---@param comment table
---@param done fun()?
function M.delete_comment(key, comment, done)
    local answer = vim.fn.confirm(('Delete this comment on %s?'):format(key), '&Yes\n&No', 2)
    if answer ~= 1 then
        return
    end

    require('qss_nvim.jira.http').jira_delete(
        ('/rest/api/3/issue/%s/comment/%s'):format(key, comment.id), function()
            changed(key, ('the comment on %s is deleted'):format(key))
            if done then
                done()
            end
        end)
end

--- What can be done with the comment under the cursor.
---@param key string
---@param comment table
---@param done fun()?
function M.comment_menu(key, comment, done)
    local mine = is_mine(comment)
    local who = comment.author and comment.author.displayName or 'someone'

    local items = { { text = ('Add another comment on %s'):format(key), idx = 1, run = function()
        M.add_comment(key)
    end } }

    if mine then
        items[#items + 1] = { text = 'Edit this comment', idx = 2, run = function()
            M.edit_comment(key, comment, done)
        end }
        items[#items + 1] = { text = 'Delete this comment', idx = 3, run = function()
            M.delete_comment(key, comment, done)
        end }
    end

    Snacks.picker({
        source = 'jira_comment',
        items = items,
        format = 'text',
        title = mine and ('Your comment on %s'):format(key) or ('%s wrote this'):format(who),
        layout = { preset = 'select' },
        confirm = function(picker, item)
            picker:close()
            if item then
                item.run()
            end
        end,
    })
end

--- Everything that can be done to an issue, in one list.
---@param key string
---@param summary string?
function M.menu(key, summary)
    local entries = {
        { text = 'Open in browser', run = M.open_in_browser },
        { text = 'Show the sprint board', run = function()
            require('qss_nvim.jira.board').open()
        end },
        { text = 'View in buffer', run = function(chosen)
            require('qss_nvim.jira.issue').open(chosen)
        end },
        { text = 'Start working on it', run = function(chosen)
            require('qss_nvim.jira.work').start(chosen, summary)
        end },
        { text = 'Transition', run = function(chosen)
            require('qss_nvim.jira.picker').transition(chosen)
        end },
        { text = 'Assign to anyone', run = M.assign },
        { text = 'Assign to me', run = M.assign_to_me },
        { text = 'Unassign', run = M.unassign },
        { text = 'Add a comment', run = M.add_comment },
        { text = 'Edit the summary', run = M.edit_summary },
        { text = 'Edit the description', run = M.edit_description },
        { text = 'Edit the labels', run = M.edit_labels },
        { text = 'Edit any field', run = function(chosen)
            require('qss_nvim.jira.fields').pick(chosen)
        end },
        { text = 'Log time in Tempo', run = function(chosen)
            require('qss_nvim.jira.tempo').log(chosen)
        end },
        { text = 'Link to another issue', run = function(chosen)
            require('qss_nvim.jira.links').pick(chosen)
        end },
        { text = 'Move to a sprint', run = M.move_to_sprint },
        { text = 'Add to an epic', run = M.add_to_epic },
        { text = 'Yank the key', run = M.yank_key },
        { text = 'Yank the URL', run = M.yank_url },
    }

    for index, entry in ipairs(entries) do
        entry.idx = index
    end

    Snacks.picker({
        source = 'jira_actions',
        items = entries,
        format = 'text',
        title = summary and ('%s  %s'):format(key, summary) or key,
        layout = { preset = 'select' },
        confirm = function(picker, item)
            picker:close()
            if item then
                item.run(key)
            end
        end,
    })
end

return M
