local M = {
    "mfussenegger/nvim-lint",
    event = "BufReadPre",
    lazy = true,
    config = function()
        require('lint').linters_by_ft = {
            python = { 'basedpyright', 'basedpyright-langserver' },
            bash = { 'shellcheck' },
            shell = { 'shellcheck' },
            sh = { 'shellcheck' },
        }
        vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
            callback = function()
                require("lint").try_lint()
            end,
        })
    end,
}

--return M
return M
