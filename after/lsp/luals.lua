local util = require("qss_nvim.utils")
---
---@type vim.lsp.Config
return {
    cmd = { 'lua-language-server' },
    -- Neovim does not export its own VIMRUNTIME to an LSP server, so a
    -- "$VIMRUNTIME" entry in a .luarc.json would find nothing without this.
    cmd_env = { VIMRUNTIME = vim.env.VIMRUNTIME },
    filetypes = { 'lua' },
    root_markers = {
        '.luarc.json',
        '.luarc.jsonc',
        '.luacheckrc',
        '.stylua.toml',
        'stylua.toml',
        'selene.toml',
        'selene.yml',
        '.git',
    },
}
