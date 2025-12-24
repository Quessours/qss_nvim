M = {
    n = {
        ["gd"] = { vim.lsp.buf.definition, "Go to definition" },
        ["gD"] = { vim.lsp.buf.declaration, "Go to declaration" },
        ["gi"] = { vim.lsp.buf.implementation, "Go to implementation" },
        ["<leader>fu"] = { vim.lsp.buf.incoming_calls, "Find usages" },
        ["<leader>fr"] = { vim.lsp.buf.references, "Find references" },
        ["<leader>td"] = { vim.lsp.buf.type_definition, "Go to type definition" },
    }
}


return M
