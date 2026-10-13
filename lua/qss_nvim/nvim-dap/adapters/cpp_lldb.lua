local build_first = require('qss_nvim.overseer.build_first')
local cmake_build = require('qss_nvim.cmake-tools.build')
local dap = require('dap')

dap.adapters.codelldb = {
    type = 'server',
    port = "${port}",
    executable = {
        -- CHANGE THIS to your path!
        command = vim.fn.stdpath('data') .. '/mason/packages/codelldb/extension/adapter/codelldb',
        args = { "--port", "${port}" },

        -- On windows you may have to uncomment this:
        -- detached = false,
    }
}

---@return table? cmake the cmake-tools module, when this is a CMake project
local function cmake_project()
    local ok, cmake = pcall(require, 'cmake-tools')
    if ok and cmake.is_cmake_project() then
        return cmake
    end
end

--- The file of the launch target cmake-tools has selected.
---@return string? path
---@return string? why there is none
local function launch_target()
    local cmake = cmake_project()
    if not cmake then
        return nil, 'not a CMake project -- use "Launch (no build)" and give a path'
    end

    local result = cmake.get_config():get_launch_target()
    if result.code ~= 0 then
        return nil, ('%s -- :CMakeSelectLaunchTarget  (<leader>ml)'):format(result.message)
    end
    if not cmake.get_config():validate_for_debugging():is_ok() then
        vim.notify(('%s is built as %s -- expect no symbols. :CMakeSelectConfigurePreset  (<leader>mp)')
            :format(cmake.get_launch_target(), cmake.get_build_type()),
            vim.log.levels.WARN, { title = 'DAP' })
    end
    return result.data
end

local function launch_program()
    if not cmake_project() then
        return vim.fn.input('Path to executable? ', vim.fn.getcwd() .. '/', 'file')
    end

    local path, why = launch_target()
    if path then
        return path
    end
    vim.notify(why, vim.log.levels.ERROR, { title = 'DAP' })
    return dap.ABORT
end

--- The launch target is checked before the build, so that a missing one is
--- reported at once and not after a build that was for nothing.
local build_and_launch = build_first.program({
    title = 'DAP',
    choose = function(on_chosen)
        local path, why = launch_target()
        if not path then
            vim.notify(why, vim.log.levels.ERROR, { title = 'DAP' })
        end
        on_chosen(path ~= nil)
    end,
    build = function()
        return cmake_build.task({
            name = 'cmake build (before debug)',
            failure = 'the build failed, so nothing was launched',
            title = 'DAP',
        })
    end,
    program = launch_target,
})

dap.configurations.cpp = {
    {
        name = "Build and launch",
        type = "codelldb",
        request = "launch",
        program = build_and_launch,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        sourceLanguages = { "cpp" }
    },
    {
        name = "Launch (no build)",
        type = "codelldb",
        request = "launch",
        program = launch_program,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        sourceLanguages = { "cpp" }
    },
}

dap.configurations.c = dap.configurations.cpp


require("qss_nvim.nvim-dap.default_mappings")
