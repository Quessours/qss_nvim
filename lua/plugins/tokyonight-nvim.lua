-- The active theme is chosen in after/plugin/colors.lua, not here: priority puts
-- tokyonight on the runtime path before any other start plugin, so the
-- colorscheme command at the end of startup always finds it loaded.
return {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    opts = {
        -- The picker and float overrides in after/plugin/colors.lua expect a
        -- transparent background. tokyonight clears the background of its own
        -- groups too, which those overrides do not reach.
        transparent = true,
        styles = {
            sidebars = 'transparent',
            floats = 'transparent',
        },
    },
}
