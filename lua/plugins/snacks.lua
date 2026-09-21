return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
        styles = {
            blame_line = {
                width = .8,
                height = .8,
                border = "double",
                title = " Git blame",
                title_pos = "left",
                ft = "git",
            }
        },
        dashboard =
            require("qss_nvim.snacks.dashboard_config"),

        explorer = { enabled = true },
        indent = { enabled = true },
        input = { enabled = true },
        picker = {
            enabled = true,
            actions = {
                -- Werid conflicts with default confirms when
                -- using file picker that opens the wrong file when starting to type a path.
                confirm = require("qss_nvim.snacks.picker").confirm,
            },
            -- Every source inherits this, files, grep and explorer alike. It is
            -- what makes <a-i>, the built-in "show ignored files too" toggle,
            -- worth pressing: without it that toggle pulls three million build
            -- artefacts into the list, with it sixteen thousand real files.
            exclude = require("qss_nvim.config.local_files").picker_exclude(),
            -- Allows Overseer and other things like CMakeTools 
            -- to use the snacks picker as the default
            ui_select = true,
            sources = {
                files = {
                    matcher = { frecency = true },
                },
            },
        },
        -- noice routes notifications into this notifier through its snacks
        -- backend, so it must stay on. See lua/plugins/noice.lua.
        notifier = { enabled = true, timeout = 3000 },
        quickfile = { enabled = true },
        scope = { enabled = true },
        scroll = { enabled = true },
        statuscolumn = { enabled = true },
        words = { enabled = true },
        zen = { enabled = true },
        dim = { enabled = true },
        git = { enabled = true }
    },
}
