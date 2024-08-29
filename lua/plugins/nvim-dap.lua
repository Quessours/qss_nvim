local M = {
    'mfussenegger/nvim-dap',
    event = "BufReadPre",
    dependencies = {
        { "theHamsta/nvim-dap-virtual-text",   lazy = true },
        { "rcarriga/nvim-dap-ui",              lazy = true },
        { "nvim-telescope/telescope-dap.nvim", lazy = true },
        { "jbyuki/one-small-step-for-vimkind", lazy = true },
        { "mfussenegger/nvim-dap-python",      lazy = true },
        { "nvim-neotest/nvim-nio",             lazy = true }
    },
    config = function()
        require('qss_nvim.nvim-dap').setup()
        require('qss_nvim.nvim-dap.utils')
    end,
    lazy = true
}


return M
