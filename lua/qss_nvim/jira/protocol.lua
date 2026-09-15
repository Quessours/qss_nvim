-- `jira://` as a real buffer name.
--
-- Every view used to be built by hand: make a scratch buffer, name it, fill it,
-- put it in a window. That works only when this module is the one opening it.
-- Nvim has a hundred other ways to open a name, and none of them worked: `gf`
-- on a key, `:edit jira://LIS-2311`, a quickfix entry, a session being
-- restored, `:bufdo`.
--
-- A BufReadCmd turns the name into the thing that loads it, so all of those
-- work and this module has one entry point instead of four.
local M = {}

local ISSUE = '^jira://(%u[%u%d]*%-%d+)$'
local SPRINT = '^jira://sprint/?(%d*)$'

---@param name string
---@return fun(buffer: integer)? loader
local function route(name)
    local key = name:match(ISSUE)
    if key then
        return function(buffer)
            local issue = require('qss_nvim.jira.issue')
            issue.prepare(buffer, key)
            issue.bind_keys(buffer, key)
            issue.load(buffer, key)
        end
    end

    if name == 'jira://board' then
        return function(buffer)
            require('qss_nvim.jira.board').adopt(buffer, 'board')
        end
    end

    if name == 'jira://backlog' then
        return function(buffer)
            require('qss_nvim.jira.board').adopt(buffer, 'backlog')
        end
    end

    -- One name, because the week is where you are in the sheet, not which sheet
    -- it is. A sprint is a different thing and earns a different address; a week
    -- is reached with < and > inside the one buffer.
    if name == 'jira://tempo' then
        return function(buffer)
            require('qss_nvim.jira.timesheet').adopt(buffer)
        end
    end

    local sprint_id = name:match(SPRINT)
    if sprint_id then
        return function(buffer)
            require('qss_nvim.jira.sprint').adopt(buffer, tonumber(sprint_id))
        end
    end

    return nil
end

--- What `gf` should open for the word under the cursor. A bare issue key becomes
--- its address; anything else is left to nvim to resolve as a path.
---@param name string
---@return string
function M.resolve(name)
    local key = name:match('^%u[%u%d]*%-%d+$')
    if key then
        return ('jira://%s'):format(key)
    end
    return name
end

function M.setup()
    vim.api.nvim_create_autocmd('BufReadCmd', {
        group = vim.api.nvim_create_augroup('QssJiraProtocol', { clear = true }),
        pattern = 'jira://*',
        desc = 'Load a Jira view from its buffer name',
        callback = function(event)
            local loader = route(event.match)
            if not loader then
                vim.bo[event.buf].buftype = 'nofile'
                vim.api.nvim_buf_set_lines(event.buf, 0, -1, false, {
                    ('%s is not a Jira address.'):format(event.match),
                    '',
                    'Try jira://LIS-1234, jira://board, jira://backlog,',
                    'jira://sprint, jira://sprint/3973 or jira://tempo.',
                })
                return
            end
            loader(event.buf)
        end,
    })
end

return M
