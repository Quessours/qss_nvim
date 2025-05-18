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
        picker = { enabled = true },
        notifier = { enabled = true, timeout = 30 },
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
