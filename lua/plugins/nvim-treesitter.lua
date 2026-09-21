local M = {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = function()
        require("nvim-treesitter.install").update({ with_sync = true })
    end,
    config = function()
        require("nvim-treesitter.configs").setup {
            ensure_installed = {
                "bash",       -- bashls (bash, sh)
                "bitbake",    -- bitbakels (.bb, .bbappend, .bbclass, layer conf)
                "c",          -- clangd
                "cpp",        -- clangd
                "doxygen",    -- injected into /** */, /*! */, /// and //! comments
                              -- by the c/cpp injection queries
                "fish",       -- fish_lsp
                "lua",        -- luals
                "python",     -- pyright
                "qmljs",      -- qmlls (qml, qmljs)
                "rust",       -- rust-analyzer, via rustaceanvim
                "sql",        -- sqls (sql, mysql)
                "javascript", -- ts_ls
                "typescript", -- ts_ls
                "tsx",        -- ts_ls (javascriptreact, typescriptreact)
                "yaml",       -- yamlls, the kas config files included
                "zig",        -- zls
            },
            highlight = {
                enable = true,
            },
            indent = {
                enable = false,
            }
        }
    end
}
return { M }
