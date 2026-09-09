local actions = require('qss_nvim.qt-property.actions')
local generate = require('qss_nvim.qt-property.generate')
local server = require('qss_nvim.qt-property.server')

---@type vim.lsp.Config
return {
    cmd = server.cmd,
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
