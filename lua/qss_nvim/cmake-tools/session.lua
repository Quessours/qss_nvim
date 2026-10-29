-- Saves the cmake-tools session as soon as it changes.
--
-- cmake-tools writes ~/.cache/cmake_tools_nvim/<cwd>.lua only on VimLeavePre
-- and when the directory changes, so a crash loses every selection since, and
-- anything reading that file in the meantime sees stale values.

local persist = require('qss_nvim.persist')

local M = {}

local NAME = 'cmake-tools'

-- cmake-tools keys the file by the cwd it captured itself, which
-- :CMakeSelectCwd leaves alone while it changes config.cwd. Tracking the same
-- value keeps these saves in the file its own exit-time save writes.
---@type string
local cwd

--- The fields session.save writes. base_settings is compared whole: the file
--- keeps only what differs from the defaults, but any change there changes
--- that difference too.
---@return string
local function snapshot()
    local config = require('cmake-tools').get_config()
    return vim.inspect({
        build_directory = config:build_directory_path(),
        build_type = config.build_type,
        variant = config.variant,
        build_target = config.build_target,
        launch_target = config.launch_target,
        kit = config.kit,
        configure_preset = config.configure_preset,
        env_script = config.env_script,
        build_preset = config.build_preset,
        test_preset = config.test_preset,
        selected_test = config.selected_test,
        base_settings = config.base_settings,
        target_settings = config.target_settings,
        cwd = config.cwd,
    })
end

local function save()
    require('cmake-tools.session').save(cwd, require('cmake-tools').get_config())
end

--- Call right after cmake-tools' setup(), which loads the session: what it
--- loaded is not a change, so startup does not rewrite the file.
function M.track()
    cwd = assert(vim.uv.cwd())
    persist.register({ name = NAME, snapshot = snapshot, save = save })

    -- Defined after cmake-tools' own DirChanged autocmd, so this runs once it
    -- has saved the old project and loaded the new one into a fresh config.
    vim.api.nvim_create_autocmd('DirChanged', {
        group = vim.api.nvim_create_augroup('qss_cmake_session', { clear = true }),
        callback = function()
            cwd = assert(vim.uv.cwd())
            persist.reset(NAME)
        end,
    })
end

return M
