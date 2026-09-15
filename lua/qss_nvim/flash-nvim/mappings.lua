local function flash()
    return require('flash')
end

-- The five upstream defaults. None of them collide: R is taken by
-- vim.lsp.buf.rename in normal mode only (nvim-lspconfig/mappings.lua:22),
-- while flash wants R in operator-pending and visual mode.
--
-- jump.pos defaults to "start" (flash/config.lua:57), which lands the cursor on
-- the first character of the match. "end" lands it on the last, so a visual
-- selection covers the typed pattern and an operator acts through it. The
-- option is passed per call rather than set in opts, because a global change
-- would also move S, r and R. flash/jump.lua:171-186 reads it.
local M = {
    n = {
        ["s"] = { function() flash().jump({ jump = { pos = 'end' } }) end, "Flash jump" },
        ["S"] = { function() flash().treesitter() end, "Flash treesitter" },
    },
    x = {
        ["s"] = { function() flash().jump({ jump = { pos = 'end' } }) end, "Flash jump" },
        ["S"] = { function() flash().treesitter() end, "Flash treesitter" },
        ["R"] = { function() flash().treesitter_search() end, "Flash treesitter search" },
    },
    o = {
        ["s"] = { function() flash().jump({ jump = { pos = 'end' } }) end, "Flash jump" },
        ["S"] = { function() flash().treesitter() end, "Flash treesitter" },
        ["r"] = { function() flash().remote() end, "Flash remote" },
        ["R"] = { function() flash().treesitter_search() end, "Flash treesitter search" },
    },
    c = {
        ["<C-s>"] = { function() flash().toggle() end, "Toggle flash search" },
    },
}

return M
