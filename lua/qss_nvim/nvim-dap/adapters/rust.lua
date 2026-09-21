-- Debugging a cargo target.
--
-- What is launched is whatever qss_nvim.cargo.state has selected, and the build
-- runs here rather than through overseer's preLaunchTask: that mechanism
-- resolves a template by name, and the builtin "cargo build" template takes no
-- profile, no features and no package, so it would build a debug binary while
-- the launch went looking for a release one.

local dap = require('dap')
local metadata = require('qss_nvim.cargo.metadata')
local state = require('qss_nvim.cargo.state')

local TITLE = 'Rust debug'

--- Split a command line the way a shell would, so that a path with a space in
--- it can be quoted and a flag keeps its dashes.
---@param line string
---@return string[]
local function split_arguments(line)
    local arguments = {}
    local current = nil
    local quote = nil

    for index = 1, #line do
        local char = line:sub(index, index)
        if quote then
            if char == quote then
                quote = nil
            else
                current = (current or '') .. char
            end
        elseif char == '"' or char == "'" then
            quote = char
            current = current or ''
        elseif char:match('%s') then
            if current then
                arguments[#arguments + 1] = current
                current = nil
            end
        else
            current = (current or '') .. char
        end
    end

    if current then
        arguments[#arguments + 1] = current
    end
    return arguments
end

--- Everything a debugger can start: the binaries, then the examples.
---@return qss.cargo.Target[]
local function launchable()
    local targets = metadata.targets('bin')
    vim.list_extend(targets, metadata.targets('example'))
    return targets
end

---@param target qss.cargo.Target
---@return string
local function label(target)
    if target.kind == 'example' then
        return ('%s  (example of %s)'):format(target.name, target.crate)
    end
    if target.name == target.crate then
        return target.name
    end
    return ('%s  (%s)'):format(target.name, target.crate)
end

--- The target to launch. The choice is remembered, so it is asked once and then
--- only when a configuration says to ask again.
---@param ask boolean ask even when one is already selected
---@param on_chosen fun(target: qss.cargo.Target?)
local function choose_target(ask, on_chosen)
    if not ask then
        local selected = state.target()
        if selected then
            return on_chosen(selected)
        end
    end

    local targets = launchable()
    if #targets == 0 then
        vim.notify('cargo reports no bin or example target here', vim.log.levels.ERROR,
            { title = TITLE })
        return on_chosen(nil)
    end
    if #targets == 1 then
        state.select_target(targets[1])
        return on_chosen(targets[1])
    end

    vim.ui.select(targets, { prompt = 'Target to debug', format_item = label },
        function(choice)
            if choice then
                state.select_target(choice)
            end
            on_chosen(choice)
        end)
end

--- The build speaks up only when it fails, because a debug session starting is
--- all the success anyone needs to see.
local BUILD_COMPONENTS = {
    'on_exit_set_status',
    { 'on_complete_notify',  statuses = { 'FAILURE' } },
    { 'on_complete_dispose', require_view = { 'FAILURE' } },
}

--- Build what is selected, in the profile and for the triple it is selected in.
---@param on_done fun(ok: boolean)
local function build(on_done)
    local overseer = require('overseer')

    local task = overseer.new_task({
        name = 'cargo build (before debug)',
        cmd = { 'cargo' },
        args = state.build_args(),
        components = BUILD_COMPONENTS,
    })

    task:subscribe('on_complete', function(_, status)
        on_done(status == 'SUCCESS')
        -- A truthy return unsubscribes, which one build is done with either way.
        return true
    end)
    task:start()
end

--- Resolve the program to launch, building it first.
---
--- nvim-dap resumes a coroutine returned by a configuration value, so the
--- launch waits here while the build runs, and gives up when it fails instead
--- of attaching to whatever the last build happened to leave behind.
---@param ask boolean ask for the target even when one is remembered
---@return fun(): thread
local function launcher(ask)
    return function()
        return coroutine.create(function(dap_co)
            choose_target(ask, function(target)
                if not target then
                    coroutine.resume(dap_co, dap.ABORT)
                    return
                end

                build(function(ok)
                    if not ok then
                        vim.notify('the build failed, so nothing was launched',
                            vim.log.levels.ERROR, { title = TITLE })
                        coroutine.resume(dap_co, dap.ABORT)
                        return
                    end

                    local artifact = state.artifact()
                    if not artifact then
                        vim.notify('cargo reports no target directory here',
                            vim.log.levels.ERROR, { title = TITLE })
                        coroutine.resume(dap_co, dap.ABORT)
                        return
                    end
                    coroutine.resume(dap_co, artifact)
                end)
            end)
        end)
    end
end

---@return string[]
local function prompt_arguments()
    return split_arguments(vim.fn.input('Arguments: '))
end

local LAUNCH = {
    type = 'codelldb',
    request = 'launch',
    cwd = '${workspaceFolder}',
    env = { RUST_BACKTRACE = '1' },
    stopOnEntry = false,
    showDisassembly = 'never',
    console = 'integratedTerminal',
    sourceLanguages = { 'rust' },
}

---@param overrides table
---@return table
local function configuration(overrides)
    return vim.tbl_extend('force', vim.deepcopy(LAUNCH), overrides)
end

dap.configurations.rust = {
    configuration({
        name = 'Launch the selected target',
        program = launcher(false),
    }),
    configuration({
        name = 'Launch the selected target with arguments',
        program = launcher(false),
        args = prompt_arguments,
    }),
    configuration({
        name = 'Choose a target, then launch it',
        program = launcher(true),
    }),
    configuration({
        -- Nothing is built for this one: it is the way to reach a binary that
        -- cargo did not produce, or one built somewhere else entirely.
        name = 'Launch a binary by path',
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
    }),
}

require('qss_nvim.nvim-dap.default_mappings')
