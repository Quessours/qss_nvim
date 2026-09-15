return {
    'saecki/crates.nvim',
    tag = 'stable',
    event = { "BufRead Cargo.toml" },
    opts = {
        -- the in-process LSP carries completion, hover and the upgrade code
        -- actions through the nvim_lsp source of nvim-cmp
        lsp = {
            enabled = true,
            actions = true,
            completion = true,
            hover = true,
        },
    },
}
