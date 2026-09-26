-- https://github.com/microsoft/pyright
--
-- `pyright`, a static type checker and language server for python

local function organize_imports(bufnr, client)
    local params = {
        command = 'pyright.organizeimports',
        arguments = { vim.uri_from_bufnr(bufnr) },
    }

    -- Sent as a plain request rather than through client:exec_cmd(). The command
    -- is private -- pyright never advertises it under executeCommandProvider --
    -- and exec_cmd refuses to call anything it cannot find advertised there.
    client:request('workspace/executeCommand', params, nil, bufnr)
end

local function set_python_path(path)
    local clients = vim.lsp.get_clients {
        bufnr = vim.api.nvim_get_current_buf(),
        name = 'pyright',
    }
    for _, client in ipairs(clients) do
        if client.settings then
            client.settings.python = vim.tbl_deep_extend('force',
                client.settings.python --[[@as table]], { pythonPath = path })
        else
            client.config.settings = vim.tbl_deep_extend('force', client.config.settings,
                { python = { pythonPath = path } })
        end
        client:notify('workspace/didChangeConfiguration', { settings = nil })
    end
end

---@type vim.lsp.Config
return {
    cmd = { 'pyright-langserver', '--stdio' },
    filetypes = { 'python' },
    root_markers = {
        'pyproject.toml',
        'setup.py',
        'setup.cfg',
        'requirements.txt',
        'Pipfile',
        'pyrightconfig.json',
        '.git',
    },
    settings = {
        python = {
            analysis = {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
            },
        },
    },
    on_attach = function(client, bufnr)
        vim.api.nvim_buf_create_user_command(bufnr, 'LspPyrightOrganizeImports', function()
            organize_imports(bufnr, client)
        end, { desc = 'Organize Imports' })

        vim.api.nvim_buf_create_user_command(bufnr, 'LspPyrightSetPythonPath', function(opts)
            set_python_path(opts.args)
        end, {
            desc = 'Reconfigure pyright with the provided python path',
            nargs = 1,
            complete = 'file',
        })
    end,
}
