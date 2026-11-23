vim.g.barbar_auto_setup = false

local options = {
    animation = true,
    auto_hide = true,
    -- An Octo review opens in its own tab page, and the buffer list of barbar
    -- is the same in each tab page. The tab page number on the right shows
    -- which tab page is current.
    tabpages = true,
    clickable = true,
    exclude_ft = {},
    exclude_name = {},

    focus_on_close = "left",
    highlight_alternate = false, -- TODO : Check what it does
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
