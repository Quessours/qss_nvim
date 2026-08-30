local function set_bg_transparent(group)
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    ---@type vim.api.keyset.highlight
    local spec = vim.tbl_extend("force", hl, { bg = "none", ctermbg = "none" })
    vim.api.nvim_set_hl(0, group, spec)
end

local accent = {
    periwinkle = "#9aa7d6",
    cyan       = "#9acfd6",
    mauve      = "#d69bb4",
    grey       = "#8b93a1",
    text       = "#c8cfdd",
}

local function set_picker_colors()
    vim.api.nvim_set_hl(0, "FloatBorder", { bg = "none", fg = accent.periwinkle })

    vim.api.nvim_set_hl(0, "SnacksNormal", { link = "Normal" })
    vim.api.nvim_set_hl(0, "SnacksNormalNC", { link = "Normal" })
    vim.api.nvim_set_hl(0, "SnacksTitle", { bg = "none", fg = accent.cyan, bold = true })
    vim.api.nvim_set_hl(0, "SnacksFooter", { bg = "none", fg = accent.grey })

    for _, group in ipairs({
        "SnacksPickerDir",
        "SnacksPickerPathHidden",
        "SnacksPickerPathIgnored",
        "SnacksPickerTotals",
        "SnacksPickerUnselected",
    }) do
        vim.api.nvim_set_hl(0, group, { bg = "none", fg = accent.grey })
    end

    vim.api.nvim_set_hl(0, "SnacksPickerMatch", { bg = "none", fg = accent.mauve, bold = true })
    vim.api.nvim_set_hl(0, "SnacksPickerPrompt", { bg = "none", fg = accent.cyan })
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

    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none", fg = accent.text })
    vim.api.nvim_set_hl(0, "LspInlayHint",
        { bg = "none", fg = "#888888", italic = true })

    set_picker_colors()
end

-- TODO : test afterglow, focuspoint, blue
Colorize("focuspoint")
