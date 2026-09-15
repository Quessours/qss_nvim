-- barbar names gitsigns as an optional dependency for the git state it draws on
-- each tab, so the plugin was installed but never set up: no signs in the sign
-- column, no staging from the buffer and no hunk textobject. The keys live in
-- qss_nvim/gitsigns-nvim/mappings.lua.
return {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = true,
}
