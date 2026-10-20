-- Debugging a cargo target.
--
-- What is launched is whatever qss_nvim.cargo.state has selected, built first
-- in the profile it is selected in. The builtin "cargo build" template takes no
-- profile, no features and no package, so it would build a debug binary while
-- the launch went looking for a release one.

local build_first = require('qss_nvim.overseer.build_first')
local cargo_diagnostics = require('qss_nvim.cargo.diagnostics')
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

--- Build what is selected, in the profile and for the triple it is selected
--- in, then launch what that build produced.
---@param ask boolean ask for the target even when one is remembered
---@return fun(): thread
local function launcher(ask)
    return build_first.program({
        title = TITLE,
        choose = function(on_chosen)
            choose_target(ask, function(target)
                on_chosen(target ~= nil)
            end)
        end,
        build = function()
            return {
                name = 'cargo build (before debug)',
                cmd = vim.list_extend({ 'cargo' }, state.build_args()),
                env = cargo_diagnostics.ENV,
                components = cargo_diagnostics.components(),
                failure = 'the build failed, so nothing was launched',
                title = TITLE,
            }
        end,
        program = function()
            return state.artifact(), 'cargo reports no target directory here'
        end,
    })
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
