-- Starting kas commands as overseer tasks.
--
-- The pickers, the user commands and the overseer templates all build their
-- command here, so that a build started from a picker and the same build
-- started from the overseer menu are the same task with the same output
-- handling.

local project = require('qss_nvim.kas.project')
local targets = require('qss_nvim.kas.targets')

local M = {}

local TITLE = 'kas'

--- Compiler output as diagnostics. The $gcc matcher reads what gcc, clang and
--- moc all print, and qss_kas_paths turns the container paths in it into paths
--- that exist on this machine. Order matters: the rewrite has to run before
--- qss_build_diagnostics places them.
---@return (string|table)[]
function M.components()
    return {
        'default',
        { 'on_output_parse', problem_matcher = '$gcc' },
        'qss_kas_paths',
        'qss_build_diagnostics',
    }
end

--- bitbake names a task either way, and `-c` is documented with the bare name.
---@param task string
---@return string
function M.task_name(task)
    return (task:gsub('^do_', ''))
end

---@param label string
---@param argv string[]?
---@return table? task
local function start(label, argv)
    if not argv then
        vim.notify('neither kas-container nor kas is installed', vim.log.levels.ERROR,
            { title = TITLE })
        return nil
    end

    local overseer = require('overseer')
    local task = overseer.new_task({
        name = label,
        cmd = { argv[1] },
        args = vim.list_slice(argv, 2),
        cwd = project.root(),
        components = M.components(),
    })

    overseer.open({ enter = false, direction = 'bottom' })
    task:start()
    return task
end

---@class qss.kas.RunOpts
---@field config string? one or more kas configs, joined by a colon
---@field target string? what to build
---@field task string? which task of the target to run, with or without do_

--- `kas build`, optionally narrowed to one target and one task.
---@param opts qss.kas.RunOpts?
---@return table? task
function M.build(opts)
    opts = opts or {}

    local args = {}
    local label = 'kas build'
    if opts.target and opts.target ~= '' then
        vim.list_extend(args, { '--target', opts.target })
        label = label .. ' ' .. opts.target
        targets.remember(opts.target)
    end
    if opts.task and opts.task ~= '' then
        local task = M.task_name(opts.task)
        vim.list_extend(args, { '-c', task })
        label = ('%s -c %s'):format(label, task)
    end

    return start(label, project.command('build', { config = opts.config, args = args }))
end

--- One command inside the build environment.
---@param command string
---@param opts qss.kas.RunOpts?
---@return table? task
function M.shell(command, opts)
    return start(('kas shell: %s'):format(command),
        project.shell_command(command, { config = (opts or {}).config }))
end

--- An interactive devshell, which is a terminal and not something to parse.
---@param recipe string
---@param opts qss.kas.RunOpts?
---@return table? task
function M.devshell(recipe, opts)
    local argv = project.shell_command(('bitbake -c devshell %s'):format(recipe),
        { config = (opts or {}).config })
    if not argv then
        vim.notify('neither kas-container nor kas is installed', vim.log.levels.ERROR,
            { title = TITLE })
        return nil
    end

    local overseer = require('overseer')
    local task = overseer.new_task({
        name = ('devshell %s'):format(recipe),
        cmd = { argv[1] },
        args = vim.list_slice(argv, 2),
        cwd = project.root(),
        components = { 'default' },
    })
    overseer.open({ enter = true, direction = 'bottom' })
    task:start()
    return task
end

---@param opts qss.kas.RunOpts?
---@return table? task
function M.checkout(opts)
    return start('kas checkout', project.command('checkout', { config = (opts or {}).config }))
end

---@param opts qss.kas.RunOpts?
---@return table? task
function M.dump(opts)
    return start('kas dump', project.command('dump', { config = (opts or {}).config }))
end

--- One command in every checked out layer repository, which is how you see at
--- once what is dirty across the whole project.
---@param command string
---@param opts qss.kas.RunOpts?
---@return table? task
function M.for_all_repos(command, opts)
    return start(('kas for-all-repos: %s'):format(command), project.command('for-all-repos', {
        config = (opts or {}).config,
        args = { command },
    }))
end

--- clean, cleansstate and cleanall are kas-container's own subcommands, and
--- plain kas does not have them.
---@param kind "clean"|"cleansstate"|"cleanall"
---@return table? task
function M.clean(kind)
    if project.runner() ~= 'kas-container' then
        vim.notify(('%s needs kas-container'):format(kind), vim.log.levels.WARN,
            { title = TITLE })
        return nil
    end
    -- An empty config keeps project.command from appending the default one:
    -- these three subcommands take no config file.
    return start('kas ' .. kind, project.command(kind, { config = '' }))
end

return M
