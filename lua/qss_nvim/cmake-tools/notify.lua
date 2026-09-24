-- A notification when a task that cmake-tools started ends.
--
-- cmake-tools has its own, but notification.lua enables it only when
-- nvim-notify loads, and the notifier here is snacks. Without one, the end of a
-- configure run is visible only in the overseer pane, and a key pressed before
-- it ends gets "A CMake task is already running".

local M = {}

--- What the cmake command line does, in one word.
---@param argv string[]
---@return string
local function verb(argv)
    for i, arg in ipairs(argv) do
        if arg == '--install' then
            return 'install'
        elseif arg == '--target' and argv[i + 1] == 'clean' then
            return 'clean'
        end
    end
    if vim.tbl_contains(argv, '--build') then
        return 'build'
    end
    return 'configure'
end

---@param task table an overseer task of the cmake-tools executor
function M.attach(task)
    local argv = type(task.cmd) == 'table' and task.cmd or { task.cmd }
    local action = verb(argv)

    task:subscribe('on_complete', function(_, status)
        local level = status == 'SUCCESS' and vim.log.levels.INFO
            or status == 'FAILURE' and vim.log.levels.ERROR
            or vim.log.levels.WARN
        local outcome = status == 'SUCCESS' and 'done'
            or status == 'FAILURE' and 'failed'
            or status:lower()
        vim.notify(('%s %s'):format(action, outcome), level, { title = 'CMake' })
        return true
    end)
end

return M
