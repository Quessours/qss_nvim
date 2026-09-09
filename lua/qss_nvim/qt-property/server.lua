local inprocess = require('lsp.inprocess')

local M = {}

---@type lsp.ServerCapabilities
local CAPABILITIES = {
    positionEncoding = 'utf-8',

    completionProvider = { resolveProvider = false },

    codeActionProvider = {
        codeActionKinds = { 'refactor.rewrite' },
        resolveProvider = false,
    },
}

---@type table<string, fun(params: table): any>
local handlers = {}

handlers['textDocument/completion'] = function(params)
    local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
    return require('qss_nvim.qt-property.complete').at(bufnr, params.position)
end

handlers['textDocument/codeAction'] = function(params)
    local uri = params.textDocument.uri
    local bufnr = vim.uri_to_bufnr(uri)
    return require('qss_nvim.qt-property.actions').at(bufnr, params.range, uri)
end

M.cmd = inprocess.cmd({
    name = 'qtprops',
    capabilities = CAPABILITIES,
    handlers = handlers,
})

return M
