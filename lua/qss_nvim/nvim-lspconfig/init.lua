---@class qss.ClientConfig : vim.lsp.ClientConfig
---@field format_on_save boolean?
---@field highlights table<string, string|vim.api.keyset.highlight>?
---@field semantic_token_highlights table<string, table<string, string|vim.api.keyset.highlight>>?
---@field filter_completion_item (fun(item: lsp.CompletionItem): boolean)?

local function set_hl(group, spec)
    vim.api.nvim_set_hl(0, group, type(spec) == 'string' and { link = spec } or spec)
end

local function apply_semantic_token_highlights(client)
    if not client then
        return
    end
    for group, spec in pairs(client.config.highlights or {}) do
        set_hl(group, spec)
    end
    local tokens = client.config.semantic_token_highlights
    if not tokens then
        return
    end
    for _, filetype in ipairs(client.config.filetypes or {}) do
        for token, spec in pairs(tokens) do
            set_hl(('@lsp.type.%s.%s'):format(token, filetype), spec)
        end
    end
end

vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('QssSemanticTokenHighlights', { clear = true }),
    desc = 'Re-apply LSP semantic token highlights',
    callback = function()
        for _, client in ipairs(vim.lsp.get_clients()) do
            apply_semantic_token_highlights(client)
        end
    end,
})

vim.api.nvim_create_autocmd('LspAttach', {
    desc = 'LSP actions',
    callback = function(event)
        local opts = { buffer = event.buf }
        local client = vim.lsp.get_client_by_id(event.data.client_id)

        apply_semantic_token_highlights(client)

        if client then
            local config = client.config --[[@as qss.ClientConfig]]
            if config.format_on_save then
                vim.api.nvim_create_autocmd('BufWritePre', {
                    group = vim.api.nvim_create_augroup(
                        ('QssFormatOnSave.%d.%d'):format(event.buf, client.id), { clear = true }),
                    buffer = event.buf,
                    desc = 'Format with ' .. client.name .. ' before writing',
                    callback = function()
                        vim.lsp.buf.format({ bufnr = event.buf, id = client.id })
                    end,
                })
            end
        end

        vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
        vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
        vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
        vim.keymap.set('n', 'R', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
        vim.keymap.set('n', 'ca', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
        vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)
        vim.keymap.set('n', 'td', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
        vim.keymap.set('n', 'th', '<cmd>lua vim.lsp.buf.typehierarchy()<cr>', opts)
        vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', opts)
        vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)
        vim.keymap.set('n', '<F2>', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
        vim.keymap.set({ 'n', 'x' }, '<F3>', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)
        vim.keymap.set('n', '<F4>', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
    end,
})
