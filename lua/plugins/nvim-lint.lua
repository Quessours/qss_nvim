return {
    "mfussenegger/nvim-lint",
    event = "BufReadPre",
    lazy = true,
    config = function()
        require("qss_nvim.nvim-lint")
    end,
}
