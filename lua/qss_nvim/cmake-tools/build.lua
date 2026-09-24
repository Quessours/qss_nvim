-- The build step other steps need to run first.
--
-- ctest runs the binaries as they were built, and a deploy copies the files as
-- they were installed, so an edit since the last build reaches neither unless
-- the build runs again. cmake and the generator behind it settle for a no-op
-- when nothing changed, which is what makes this cheap enough to always do.

local diagnostics = require('qss_nvim.cmake-tools.diagnostics')
local state = require('qss_nvim.cmake-tools.state')

local M = {}

--- The build the :CMake* commands would run, in the configuration they use.
---@return string[]
function M.args()
    local preset = state.usable_preset('build')
    local args
    if preset then
        args = { '--build', '--preset', preset }
    else
        args = { '--build', state.build_dir(), '--parallel' }
    end
    vim.list_extend(args, state.build_options())
    return args
end

--- A build that runs ahead of something else speaks up only when it fails,
--- because what the step after it is there to show is that step's own output.
local COMPONENTS = {
    'on_exit_set_status',
    { 'on_complete_notify',  statuses = { 'FAILURE' } },
    { 'on_complete_dispose', require_view = { 'FAILURE' } },
}

---@class qss.cmake.BuildFirst
---@field label string the task name
---@field failure string what to say when the build fails
---@field title string the notification title

---@param opts qss.cmake.BuildFirst
---@param on_success fun()
function M.first(opts, on_success)
    local overseer = require('overseer')
    local components = vim.deepcopy(COMPONENTS)
    vim.list_extend(components, diagnostics.components())

    local task = overseer.new_task({
        name = opts.label,
        cmd = { 'cmake' },
        args = M.args(),
        components = components,
    })

    task:subscribe('on_complete', function(_, status)
        if status == 'SUCCESS' then
            on_success()
        else
            vim.notify(opts.failure, vim.log.levels.ERROR, { title = opts.title })
        end
        -- A truthy return unsubscribes, which one build is done with either way.
        return true
    end)
    task:start()
end

return M
