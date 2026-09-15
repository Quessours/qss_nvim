-- The branch name is the only place the issue key already lives, so it is what
-- lets every key work with no argument. git is local and answers in a few
-- milliseconds, so these calls stay blocking.
local M = {}

local TITLE = 'Jira'

-- LIS-123, and the same shape for any other project. The %f frontier stops the
-- match in the middle of a word, so `refs/ABC-1` matches and `xLIS-123` does not.
local KEY = '%f[%w]%u[%u%d]*%-%d+'

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param args string[]
---@return string[] lines, boolean ok
local function git(args)
    local cmd = { 'git' }
    vim.list_extend(cmd, args)
    local lines = vim.fn.systemlist(cmd)
    return lines, vim.v.shell_error == 0
end

--- The branch checked out right now.
---@return string?
function M.branch()
    local lines, ok = git({ 'branch', '--show-current' })
    local name = ok and vim.trim(lines[1] or '') or ''
    if name == '' then
        return nil
    end
    return name
end

--- The issue key carried by the current branch name.
---@return string?
function M.issue_key()
    local branch = M.branch()
    if not branch then
        return nil
    end
    return branch:match(KEY)
end

--- A summary turned into the tail of a branch name.
---@param summary string
---@return string
local function slug(summary)
    local dashed = summary:lower():gsub('[^%w]+', '-')
    local trimmed = dashed:gsub('^%-+', ''):gsub('%-+$', '')
    return (trimmed:sub(1, 50):gsub('%-+$', ''))
end

--- Create the branch of an issue and switch to it. The base is whatever is
--- checked out, which the notification names so a nested branch is visible.
---@param key string
---@param summary string?
---@param callback fun()?
function M.create_branch(key, summary, callback)
    local base = M.branch()
    if not base then
        return notify('this is not a git work tree', vim.log.levels.ERROR)
    end

    local prefix = require('qss_nvim.jira.config').options.branch_prefix
    local tail = summary and summary ~= '' and ('-%s'):format(slug(summary)) or ''
    local name = ('%s%s%s'):format(prefix, key, tail)

    local existing = git({ 'rev-parse', '--verify', '--quiet', name })
    local args = #existing > 0 and { 'switch', name } or { 'switch', '--create', name }

    local _, ok = git(args)
    if not ok then
        return notify(('could not switch to %s'):format(name), vim.log.levels.ERROR)
    end

    notify(('%s, from %s'):format(name, base), vim.log.levels.INFO)
    if callback then
        callback()
    end
end

--- Put the issue key of the branch at the start of the commit message.
---@param buffer integer
local function prefix_commit(buffer)
    local key = M.issue_key()
    if not key then
        return
    end

    local first = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ''
    if first ~= '' then
        return
    end

    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { ('%s '):format(key) })
    vim.api.nvim_win_set_cursor(0, { 1, #key + 1 })
end

--- The gitcommit buffer gets the key of the branch, and <leader>jk to insert it
--- again after an edit wiped it.
function M.setup_commit_buffer()
    vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('QssJiraCommit', { clear = true }),
        pattern = 'gitcommit',
        desc = 'Put the Jira issue key of the branch in the commit message',
        callback = function(event)
            local key = M.issue_key()
            if not key then
                return
            end

            vim.keymap.set('n', '<leader>jk', function()
                vim.api.nvim_put({ key }, 'c', true, true)
            end, { buffer = event.buf, desc = 'Insert the Jira issue key' })

            if require('qss_nvim.jira.config').options.commit_prefix then
                prefix_commit(event.buf)
            end
        end,
    })
end

return M
