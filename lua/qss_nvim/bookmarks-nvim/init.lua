return {
    keymap = require("qss_nvim.bookmarks-nvim.mappings"),
    width = 0.8,                                                                                -- Bookmarks window width:  (0, 1]
    height = 0.6,                                                                               -- Bookmarks window height: (0, 1]
    preview_ratio = 0.7,                                                                        -- Bookmarks preview window ratio (0, 1]
    preview_ext_enable = false,                                                                 -- If true, preview buf will add file ext, preview window may be highlighed(treesitter), but may be slower.
    fix_enable = false,                                                                         -- If true, when saving the current file, if the bookmark line number of the current file changes, try to fix it.

    virt_text = "🔖",                                                                         -- Show virt text at the end of bookmarked lines
    virt_pattern = { "*.go", "*.lua", "*.sh", "*.php", "*.rs", "*.cpp", "*.h", "*.c", "*.sh" }, -- Show virt text only on matched pattern
    border_style = "single",                                                                    -- border style: "single", "double", "rounded"
    hl = {
        border = "TelescopeBorder",                                                             -- border highlight
        cursorline = "guibg=Gray guifg=White",                                                  -- cursorline highlight
    }
}
