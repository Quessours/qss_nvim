-- Change this one line to switch theme. Every name shipped by tokyonight
-- ("tokyonight-night", "tokyonight-storm", "tokyonight-moon", "tokyonight-day")
-- and every name shipped by awesome-vim-colorschemes ("focuspoint",
-- "afterglow", "blue"...) is valid here.
local color_theme = "tokyonight-night"

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
    sage       = "#a4d69a",
    sand       = "#d6c49a",
    rose       = "#d69a9a",
    ink        = "#16161e",
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

-- octo.nvim colors its bubbles (the pills around a count or a state) with a
-- fixed palette of its own. The octo spec sets the bubble delimiters to one
-- space, so the delimiter groups take the bubble colors and pad the pill.
-- octo.nvim defines its groups with default = true, so these win.
local function set_octo_colors()
    local bubbles = {
        Blue   = accent.periwinkle,
        Purple = accent.mauve,
        Grey   = accent.grey,
        Green  = accent.sage,
        Yellow = accent.sand,
        Red    = accent.rose,
    }
    for name, color in pairs(bubbles) do
        vim.api.nvim_set_hl(0, "OctoBubble" .. name, { bg = color, fg = accent.ink })
        vim.api.nvim_set_hl(0, "OctoBubbleDelimiter" .. name, { link = "OctoBubble" .. name })
    end
end

function Colorize(theme)
    vim.cmd.colorscheme(theme or color_theme)

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
    set_octo_colors()
end

Colorize(color_theme)
