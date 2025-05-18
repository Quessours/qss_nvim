vim.api.nvim_create_autocmd("BufWritePre", {
    buffer = buffer,
    callback = function()
        vim.lsp.buf.format { async = false }
    end
})
--[[
vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)

        if client:supports_method('textDocument/completion') then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        end
    end,
})

vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)

        if client:supports_method('textDocument/inlayHint') then
            vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
        end
    end,
})
vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)

        if client:supports_method('textDocument/documentHighlight') then
            local autocmd = vim.api.nvim_create_autocmd
            local augroup = vim.api.nvim_create_augroup('lsp_highlight', { clear = false })

            vim.api.nvim_clear_autocmds({ buffer = bufnr, group = augroup })

            autocmd({ 'CursorHold' }, {
                group = augroup,
                buffer = args.buf,
                callback = vim.lsp.buf.document_highlight,
            })

            autocmd({ 'CursorMoved' }, {
                group = augroup,
                buffer = args.buf,
                callback = vim.lsp.buf.clear_references,
            })
        end
    end,
})
vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'noinsert' }
vim.opt.shortmess:append('c')

local function tab_complete()
    if vim.fn.pumvisible() == 1 then
        -- navigate to next item in completion menu
        return '<Down>'
    end

    local c = vim.fn.col('.') - 1
    local is_whitespace = c == 0 or vim.fn.getline('.'):sub(c, c):match('%s')

    if is_whitespace then
        -- insert tab
        return '<Tab>'
    end

    local lsp_completion = vim.bo.omnifunc == 'v:lua.vim.lsp.omnifunc'

    if lsp_completion then
        -- trigger lsp code completion
        return '<C-x><C-o>'
    end

    -- suggest words in current buffer
    return '<C-x><C-n>'
end

local function tab_prev()
    if vim.fn.pumvisible() == 1 then
        -- navigate to previous item in completion menu
        return '<Up>'
    end

    -- insert tab
    return '<Tab>'
end

vim.keymap.set('i', '<Tab>', tab_complete, { expr = true })
vim.keymap.set('i', '<S-Tab>', tab_prev, { expr = true })
--]]
