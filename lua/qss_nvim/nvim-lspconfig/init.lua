---@class qss.ClientConfig : vim.lsp.ClientConfig
---@field format_on_save boolean?
---@field highlights table<string, string|vim.api.keyset.highlight>?
---@field semantic_token_highlights table<string, table<string, string|vim.api.keyset.highlight>>?
---@field filter_completion_item (fun(item: lsp.CompletionItem): boolean)?

if vim.g.qss_format_on_save == nil then
    vim.g.qss_format_on_save = true
end

vim.api.nvim_create_user_command('QssFormatOnSave', function()
    vim.g.qss_format_on_save = not vim.g.qss_format_on_save
    vim.notify('Format on save ' .. (vim.g.qss_format_on_save and 'enabled' or 'disabled'))
end, { desc = 'Toggle format on save for this session' })

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
                        if not vim.g.qss_format_on_save then
                            return
                        end
                        vim.lsp.buf.format({ bufnr = event.buf, id = client.id })
                    end,
                })
            end
        end
    end,
})
