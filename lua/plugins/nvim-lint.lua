local M = {
    "mfussenegger/nvim-lint",
    event = "BufReadPre",
    lazy = true,
    config = function()
        vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
            callback = function()
                require("lint").try_lint()
            end,
        })
    end,
}

--return M
return M
