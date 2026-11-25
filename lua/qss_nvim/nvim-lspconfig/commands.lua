-- On Neovim 0.12, nvim-lspconfig creates no :Lsp* commands, because Neovim has
-- the built-in :lsp command. These user commands keep the old names and run
-- the Neovim 0.12 equivalent.

---@param info { fargs: string[] }
---@return string arguments The client names of the command, joined by spaces.
local function client_names(info)
    return table.concat(info.fargs, ' ')
end

---@return string[] names The names of the running LSP clients.
local function complete_clients()
    return vim.tbl_map(function(client) return client.name end, vim.lsp.get_clients())
end

vim.api.nvim_create_user_command('LspInfo', 'checkhealth vim.lsp', {
    desc = 'Show the LSP health report',
})

vim.api.nvim_create_user_command('LspRestart', function(info)
    vim.cmd('lsp restart ' .. client_names(info))
end, {
    desc = 'Restart the given LSP clients, or the clients of the buffer',
    nargs = '*',
    complete = complete_clients,
})

vim.api.nvim_create_user_command('LspStop', function(info)
    vim.cmd('lsp stop ' .. client_names(info))
end, {
    desc = 'Stop the given LSP clients, or the clients of the buffer',
    nargs = '*',
    complete = complete_clients,
})

vim.api.nvim_create_user_command('LspLog', function()
    vim.cmd.tabnew(vim.lsp.log.get_filename())
end, {
    desc = 'Open the LSP log in a new tab',
})
