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
            -- Off by default: in a file with dozens of matches for a common
            -- word, a label on every one of them gets in the way, and search
            -- mode also clears hlsearch on jump. <C-s> turns the labels on
            -- from the command line for the searches that want them.
            search = { enabled = false },
        },
    },
}
