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
    'yamlls',
})

-- The right side of an Octo review diff is an octo:// buffer with an empty
-- buftype, so vim.lsp.enable starts the servers of its filetype for it. clangd
-- rejects each request on a URI other than file://, and the other servers
-- cannot read the file either. When a server attaches to a buffer that is not
-- a local file, the server leaves the buffer.
vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local is_local_file = vim.startswith(vim.uri_from_bufnr(args.buf), 'file://')
        if is_local_file then
            return
        end
        vim.schedule(function()
            vim.lsp.buf_detach_client(args.buf, args.data.client_id)
        end)
    end,
})
