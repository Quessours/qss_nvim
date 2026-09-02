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

local function launch_program()
    local ok, cmake = pcall(require, 'cmake-tools')
    if not (ok and cmake.is_cmake_project()) then
        return vim.fn.input('Path to executable? ', vim.fn.getcwd() .. '/', 'file')
    end

    local result = cmake.get_config():get_launch_target()
    if result.code == 0 then
        if not cmake.get_config():validate_for_debugging():is_ok() then
            vim.notify(('%s is built as %s -- expect no symbols. :CMakeSelectConfigurePreset  (<leader>mp)')
                :format(cmake.get_launch_target(), cmake.get_build_type()),
                vim.log.levels.WARN, { title = 'DAP' })
        end
        return result.data
    end

    vim.notify(('%s -- :CMakeSelectLaunchTarget  (<leader>ml)'):format(result.message),
        vim.log.levels.ERROR, { title = 'DAP' })
    return dap.ABORT
end

dap.configurations.cpp = {
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
