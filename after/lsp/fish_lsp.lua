-- https://github.com/ndonfris/fish-lsp
--
-- A Language Server Protocol (LSP) tailored for the fish shell. Auto-completion,
-- scope aware symbol analysis, per-token hover generation, and many others.
--
-- [homepage](https://www.fish-lsp.dev/)

---@type vim.lsp.Config
return {
    cmd = { 'fish-lsp', 'start' },
    filetypes = { 'fish' },
    root_markers = { 'config.fish', '.git' },
}
