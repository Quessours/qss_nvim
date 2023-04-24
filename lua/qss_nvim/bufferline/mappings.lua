M = { n = {
	["<TAB>"] = { "<cmd> BufferLineCycleNext <CR>", "Go to next tab"},
	["<S-TAB>"] = { "<cmd> BufferLineCyclePrev <CR>", "Go to previous tab"},
	["<leader>ct"] = { "<cmd> BufferLinePickClose <CR>", "Close chosen tab"},
	["<leader>ot"] = { "<cmd> BufferLinePick <CR>", "Open chosen tab"},
}
}

return M
