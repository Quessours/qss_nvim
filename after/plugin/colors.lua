function Colorize(color_theme)
    color_theme = color_theme or "focuspoint"
    vim.cmd.colorscheme(color_theme)

    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    vim.api.nvim_set_hl(0, "EndOfBuffer", { bg = "none" })
    vim.api.nvim_set_hl(0, "WinSeparator", { bg = "none" })
    vim.api.nvim_set_hl(0, "LineNrAbove", { bg = "none" })
    vim.api.nvim_set_hl(0, "LineNrBelow", { bg = "none" })
    vim.api.nvim_set_hl(0, "TabLine", { bg = "none" })
    vim.api.nvim_set_hl(0, "TabLineFill", { bg = "none" })
    vim.api.nvim_set_hl(0, "TabLineSel", { bg = "none" })

    --require("qss_nvim.bufferline")
end

-- TODO : test afterglow, focuspoint, blue
Colorize("focuspoint")
