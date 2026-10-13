-- The build that runs ahead of something else: the tests, a deploy, a debug
-- session.
--
-- Every caller wants the same thing. The build is quiet when it works, because
-- what comes after it is what there is to see. When it fails, the log opens,
-- where <CR> on an error opens its file (output_jump.lua), and what was to come
-- after it does not happen.
--
-- A debug session builds through program() below, and not through overseer's
-- preLaunchTask. That one resolves a template by name and passes it no
-- parameters, so it cannot build the selected target, preset or profile.

local M = {}

local COMPONENTS = {
    'on_exit_set_status',
    { 'on_complete_dispose', require_view = { 'FAILURE' } },
    { 'open_output',         on_start = 'never', on_complete = 'failure' },
}

---@class qss.overseer.BuildFirst
---@field name string the task name
---@field cmd string[] the command line, program first
---@field cwd string?
---@field components table[]? what parses the output, if anything does
---@field failure string what to say when the build fails
---@field title string the notification title

--- Run the build, then call back with whether it worked. A failure is already
--- reported by the time `on_done` runs.
---@param opts qss.overseer.BuildFirst
---@param on_done fun(ok: boolean)
function M.run(opts, on_done)
    local components = vim.deepcopy(COMPONENTS)
    vim.list_extend(components, opts.components or {})

    local task = require('overseer').new_task({
        name = opts.name,
        cmd = opts.cmd,
        cwd = opts.cwd,
        components = components,
    })

    task:subscribe('on_complete', function(_, status)
        local ok = status == 'SUCCESS'
        if not ok then
            vim.notify(opts.failure, vim.log.levels.ERROR, { title = opts.title })
        end
        on_done(ok)
        -- A truthy return unsubscribes, which one build is done with either way.
        return true
    end)
    task:start()
end

---@class qss.overseer.BuildThenLaunch
---@field title string the notification title
---@field choose? fun(on_chosen: fun(ok: boolean)) a step before the build, such as picking the target
---@field build fun(): qss.overseer.BuildFirst?, string? the build, or nil and why there is none
---@field program fun(): string?, string? the file to launch, or nil and why there is none

--- A `program` value for a dap configuration that builds before it launches.
---
--- nvim-dap resumes a coroutine returned by a configuration value, so the
--- launch waits here while the build runs, and gives up when it fails instead
--- of starting whatever the last build happened to leave behind.
---@param launch qss.overseer.BuildThenLaunch
---@return fun(): thread
function M.program(launch)
    return function()
        local dap = require('dap')
        return coroutine.create(function(dap_co)
            ---@param why string?
            local function abort(why)
                if why then
                    vim.notify(why, vim.log.levels.ERROR, { title = launch.title })
                end
                coroutine.resume(dap_co, dap.ABORT)
            end

            local function after_build(ok)
                if not ok then
                    return abort()
                end
                local path, why = launch.program()
                if not path then
                    return abort(why)
                end
                coroutine.resume(dap_co, path)
            end

            local function start(ok)
                if not ok then
                    return abort()
                end
                local opts, why = launch.build()
                if not opts then
                    return abort(why)
                end
                M.run(opts, after_build)
            end

            if launch.choose then
                launch.choose(start)
            else
                start(true)
            end
        end)
    end
end

return M
