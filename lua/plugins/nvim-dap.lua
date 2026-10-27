local M = {
    'mfussenegger/nvim-dap',
    dependencies = {
        { "theHamsta/nvim-dap-virtual-text",   lazy = true },
        { "jbyuki/one-small-step-for-vimkind", lazy = true },
        { "mfussenegger/nvim-dap-python",      lazy = true },
        { "nvim-neotest/nvim-nio",             lazy = true }
    },
    -- The first require('dap') loads the plugin, from the <leader>d keys, the
    -- cmake deploy or a preLaunchTask. The keys are set here because the adapter
    -- files that also set them only run once the plugin is loaded.
    init = function()
        require('qss_nvim.nvim-dap.default_mappings')
    end,
    cmd = {
        "DapContinue", "DapNew", "DapToggleBreakpoint", "DapClearBreakpoints",
        "DapToggleRepl", "DapStepOver", "DapStepInto", "DapStepOut", "DapPause",
        "DapTerminate", "DapDisconnect", "DapRestartFrame", "DapEval",
        "DapSetLogLevel", "DapShowLog",
    },
    config = function()
        require('qss_nvim.nvim-dap').setup()
        require('qss_nvim.nvim-dap.utils')
    end,
    lazy = true
}


return M
