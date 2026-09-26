-- Each server reads its configuration from after/lsp/<name>.lua. after/ comes
-- last on the runtimepath, so these files win over the lsp/<name>.lua that
-- nvim-lspconfig ships for the same server.
vim.lsp.enable({
    'luals',
    'clangd',
    'zls',
    'bashls',
    'fish_lsp',
    'pyright',
    'ts_ls',
    'sqls',
    'plantuml',
    'qmlls',
    'qtprops',
    'cppimpl',
    'bitbakels',
    'yamlls',
})
