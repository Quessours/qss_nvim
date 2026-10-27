-- The main branch only installs parsers and queries: highlighting is Neovim's
-- own, started below. It needs the tree-sitter CLI on PATH to build a parser,
-- and it does not support lazy-loading.
local ensure_installed = {
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
}

return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
        require("nvim-treesitter").install(ensure_installed)

        -- Every filetype with an installed parser, as the master branch did with
        -- highlight.enable.
        vim.api.nvim_create_autocmd("FileType", {
            callback = function(args)
                local lang = vim.treesitter.language.get_lang(args.match)
                if not lang then
                    return
                end
                local has_parser = vim.treesitter.language.add(lang)
                if has_parser then
                    vim.treesitter.start(args.buf, lang)
                end
            end,
        })
    end,
}
