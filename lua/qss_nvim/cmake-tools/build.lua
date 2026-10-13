-- The build step other steps need to run first.
--
-- ctest runs the binaries as they were built, and a deploy copies the files as
-- they were installed, so an edit since the last build reaches neither unless
-- the build runs again. cmake and the generator behind it settle for a no-op
-- when nothing changed, which is what makes this cheap enough to always do.

local build_first = require('qss_nvim.overseer.build_first')
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

---@class qss.cmake.BuildFirst
---@field name string the task name
---@field failure string what to say when the build fails
---@field title string the notification title

--- The build, with its errors parsed into diagnostics.
---@param opts qss.cmake.BuildFirst
---@return qss.overseer.BuildFirst
function M.task(opts)
    return {
        name = opts.name,
        cmd = vim.list_extend({ 'cmake' }, M.args()),
        components = diagnostics.components(),
        failure = opts.failure,
        title = opts.title,
    }
end

--- The build, then `on_success`.
---@param opts qss.cmake.BuildFirst
---@param on_success fun()
function M.first(opts, on_success)
    build_first.run(M.task(opts), function(ok)
        if ok then
            on_success()
        end
    end)
end

return M
