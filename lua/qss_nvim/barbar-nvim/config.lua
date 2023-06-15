vim.g.barbar_auto_setup = false

local options = {
    animation = true,
    auto_hide = true,
    tabpages = false,
    clickable = true,
    exclude_ft = {},
    exclude_name = {},

    focus_on_close = "left",
    highlight_alternate = true, -- TODO : Check what it does
    highlight_inactive_file_icons = true,
    insert_at_end = false,
    insert_at_start = false,

    maximum_length = 25,
    minimum_length = 10,

    semantic_letters = true,

    sidebar_filetypes = {
        NvimTree = true
    }


}

return options
