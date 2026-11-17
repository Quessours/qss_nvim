-- Gives the program that :CMakeRun and :CMakeDebug start the environment of
-- the selected configure preset, as Qt Creator and the VS Code CMake extension
-- do.
--
-- cmake-tools builds the run environment from base_settings.env and
-- target_settings[target].env only. The preset environment reaches cmake
-- itself, never the program. A value in target_settings still wins over the
-- preset, so :CMakeTargetSettings can override one variable for one target.

local M = {}

---@return table<string, string>
local function configure_preset_environment()
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    if not ok then
        return {}
    end
    local config = cmake_tools.get_config()
    if not config.configure_preset then
        return {}
    end
    local presets = require('cmake-tools.presets'):parse(config.cwd)
    local preset = presets:get_configure_preset(config.configure_preset, { include_hidden = true })
    if not preset then
        return {}
    end
    -- A null in the preset removes a variable that a parent set.
    return vim.iter(preset.environment or {})
        :filter(function(_, value)
            return value ~= vim.NIL
        end)
        :fold({}, function(environment, name, value)
            environment[name] = value
            return environment
        end)
end

--- Call from cmake_runner.opts.on_new_task, which cmake-tools runs before the
--- task starts.
---@param task overseer.Task
function M.attach(task)
    task.env = vim.tbl_extend('keep', task.env or {}, configure_preset_environment())
end

-- cmake-tools merges cmake_dap_configuration into every launch :CMakeDebug
-- starts, and into no other one, so this field marks the launches to extend.
-- The listener removes it before the adapter sees the configuration.
M.DAP_MARKER = 'qss_configure_preset_environment'

function M.register_dap_listener()
    local ok, dap = pcall(require, 'dap')
    if not ok then
        return
    end
    dap.listeners.on_config[M.DAP_MARKER] = function(config)
        if not config[M.DAP_MARKER] then
            return config
        end
        local extended = vim.deepcopy(config)
        extended[M.DAP_MARKER] = nil
        extended.env = vim.tbl_extend('keep', extended.env or {}, configure_preset_environment())
        return extended
    end
end

return M
