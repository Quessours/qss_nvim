-- Starting a ticket is five small changes that are always made together and
-- always in the same order. Each one waits for the one before it, because a
-- transition that runs before the assignment can be refused by the workflow.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local cli = require('qss_nvim.jira.cli')
local config = require('qss_nvim.jira.config')
local git = require('qss_nvim.jira.git')

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@param key string
---@param continue fun()
local function assign(key, continue)
    local instance = config.instance()
    if not (instance and instance.login) then
        return notify('the login is missing from the jira-cli config', vim.log.levels.ERROR)
    end
    cli.write({ 'issue', 'assign', key, instance.login }, '', continue)
end

---@param key string
---@param continue fun()
local function move_to_sprint(key, continue)
    require('qss_nvim.jira.picker').list_sprints('active', function(sprints)
        if #sprints == 0 then
            notify('no active sprint on the board, so the issue stays where it is', vim.log.levels.WARN)
            return continue()
        end

        if #sprints > 1 then
            return require('qss_nvim.jira.picker').sprints(function(chosen)
                cli.write({ 'sprint', 'add', chosen.id, key }, '', continue)
            end)
        end
        cli.write({ 'sprint', 'add', sprints[1].id, key }, '', continue)
    end)
end

---@param key string
---@param continue fun()
local function transition(key, continue)
    local target = config.options.start_work_transition
    cli.write({ 'issue', 'move', key, target }, '', continue)
end

---@param key string
---@param summary string?
---@param continue fun()
local function branch(key, summary, continue)
    git.create_branch(key, summary, continue)
end

---@param key string
---@param continue fun()
local function yank(key, continue)
    vim.fn.setreg('+', key)
    continue()
end

--- Run the whole flow. A step that is switched off in config.options is skipped
--- rather than reported.
---@param key string
---@param summary string?
function M.start(key, summary)
    local steps = config.options.start_work_steps
    local queue = {}

    if steps.assign then
        queue[#queue + 1] = function(continue) assign(key, continue) end
    end
    if steps.sprint then
        queue[#queue + 1] = function(continue) move_to_sprint(key, continue) end
    end
    if steps.transition then
        queue[#queue + 1] = function(continue) transition(key, continue) end
    end
    if steps.branch then
        queue[#queue + 1] = function(continue) branch(key, summary, continue) end
    end
    if steps.yank then
        queue[#queue + 1] = function(continue) yank(key, continue) end
    end

    local position = 0

    local function advance()
        position = position + 1
        local step = queue[position]
        if not step then
            require('qss_nvim.jira.edit').landed(key)
            return notify(('you are working on %s'):format(key), vim.log.levels.INFO)
        end
        step(advance)
    end

    advance()
end

return M
