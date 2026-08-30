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

-- CMake projects go through :CMakeDebug, which builds the selected launch target
-- and hands dap the resolved binary. This one is the fallback for everything
-- else, so it asks for a path and builds nothing.
dap.configurations.cpp = {
    {
        name = "Launch file (no build)",
        type = "codelldb",
        request = "launch",
        program = function()
            return vim.fn.input('Path to executable? ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        sourceLanguages = { "cpp" }
    },
}

dap.configurations.c = dap.configurations.cpp


require("qss_nvim.nvim-dap.default_mappings")
