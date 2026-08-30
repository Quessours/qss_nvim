-- Every LSP key lives here. They used to be split between this table and a
-- second set created buffer-locally on LspAttach, where the buffer-local copies
-- shadowed gd, gD and gi and left the ones here unreachable in any LSP buffer.
--
-- Navigation goes through snacks.picker rather than vim.lsp.buf: the built-ins
-- push their results straight into the quickfix list, which in a Qt or C++ tree
-- means scrolling a flat list of dozens of hits with no preview and no filter.
M = {
    n = {
        ["gd"] = { function() Snacks.picker.lsp_definitions() end, "Go to definition" },
        ["gD"] = { function() Snacks.picker.lsp_declarations() end, "Go to declaration" },
        ["gi"] = { function() Snacks.picker.lsp_implementations() end, "Go to implementation" },
        ["gr"] = { function() Snacks.picker.lsp_references() end, "Find references" },
        ["td"] = { function() Snacks.picker.lsp_type_definitions() end, "Go to type definition" },
        ["<leader>fr"] = { function() Snacks.picker.lsp_references() end, "Find references" },
        ["<leader>fu"] = { function() Snacks.picker.lsp_incoming_calls() end, "Find usages" },
        ["<leader>td"] = { function() Snacks.picker.lsp_type_definitions() end, "Go to type definition" },
        ["<leader>fw"] = { function() Snacks.picker.lsp_workspace_symbols() end, "Find symbol in workspace" },
        ["<leader>fo"] = { function() Snacks.picker.lsp_symbols() end, "Find symbol in document" },

        ["K"] = { vim.lsp.buf.hover, "Hover" },
        ["R"] = { vim.lsp.buf.rename, "Rename symbol" },
        ["<F2>"] = { vim.lsp.buf.rename, "Rename symbol" },
        ["ca"] = { vim.lsp.buf.code_action, "Code action" },
        ["<F4>"] = { vim.lsp.buf.code_action, "Code action" },
        ["gs"] = { vim.lsp.buf.signature_help, "Signature help" },
        ["th"] = { vim.lsp.buf.typehierarchy, "Type hierarchy" },
        ["<F3>"] = { function() vim.lsp.buf.format({ async = true }) end, "Format buffer" },
    },
    x = {
        ["<F3>"] = { function() vim.lsp.buf.format({ async = true }) end, "Format selection" },
    }
}


return M
