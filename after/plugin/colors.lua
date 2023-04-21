function Colorize(color_theme)
	color_theme = color_theme or "focuspoint"
	vim.cmd.colorscheme(color_theme)

	--vim.api.nvim_set_hl(0, "Normal", { bg = "none"})
	--vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none"})
end


Colorize("onehalfdark")
