local function set_bg_transparent(group)
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    ---@type vim.api.keyset.highlight
    local spec = vim.tbl_extend("force", hl, { bg = "none", ctermbg = "none" })
    vim.api.nvim_set_hl(0, group, spec)
end

function Colorize(color_theme)
    color_theme = color_theme or "focuspoint"
    vim.cmd.colorscheme(color_theme)

    set_bg_transparent("Normal")
    set_bg_transparent("EndOfBuffer")
    set_bg_transparent("WinSeparator")
    set_bg_transparent("LineNrAbove")
    set_bg_transparent("LineNrBelow")
    set_bg_transparent("TabLine")
    set_bg_transparent("TabLineFill")
    set_bg_transparent("TabLineSel")

    vim.api.nvim_set_hl(0, "StatusLine", { bg = "none", ctermbg = "none", fg = "#666666" })

    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none", fg = "NvimLightYellow" })
    vim.api.nvim_set_hl(0, "LspInlayHint",
        { bg = "none", fg = "#888888", italic = true })
end

-- TODO : test afterglow, focuspoint, blue
Colorize("focuspoint")
