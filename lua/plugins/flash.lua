-- flash labels every match of a motion so one keypress jumps to it. The keys
-- live in qss_nvim/flash-nvim/mappings.lua next to every other mapping.
--
-- VeryLazy rather than a `keys` list, because the f/t enhancement below is set
-- up when the plugin loads. Loading on `s` alone would leave f, t, ; and ,
-- unenhanced until the first jump of a session.
return {
    'folke/flash.nvim',
    event = 'VeryLazy',
    opts = {
        modes = {
            -- f, t, F and T jump across lines, and ; and , repeat the motion
            -- rather than only the last f/t. Set enabled = false to get the
            -- stock Vim behaviour back.
            char = { enabled = true },
            -- label the matches of / and ? while the search is being typed.
            -- <C-s> toggles it from the command line.
            search = { enabled = true },
        },
    },
}
