local actions = require('qss_nvim.cpp-impl.actions')
local generate = require('qss_nvim.cpp-impl.generate')
local inprocess = require('lsp.inprocess')

---@type lsp.ServerCapabilities
local CAPABILITIES = {
    positionEncoding = 'utf-8',

    codeActionProvider = {
        codeActionKinds = { 'refactor.rewrite' },
        resolveProvider = false,
    },
}

---@type table<string, fun(params: table): any>
local handlers = {}

handlers['textDocument/codeAction'] = function(params)
    local uri = params.textDocument.uri
    return actions.at(vim.uri_to_bufnr(uri), params.range, uri)
end

---@type vim.lsp.Config
return {
    cmd = inprocess.cmd({
        name = 'cppimpl',
        capabilities = CAPABILITIES,
        handlers = handlers,
    }),
    filetypes = { 'c', 'cpp', 'c.doxygen', 'cpp.doxygen', 'objcpp' },
    commands = {
        [actions.COMMAND] = function(command)
            local arguments = command.arguments or {}
            local uri, row = arguments[1], arguments[2]
            if type(uri) ~= 'string' or type(row) ~= 'number' then
                return
            end

            local bufnr = vim.uri_to_bufnr(uri)
            vim.fn.bufload(bufnr)
            generate.run(bufnr, row)
        end,
    },
}
