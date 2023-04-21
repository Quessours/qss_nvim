-- local builtin = require('telescope.builtin')
-- vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
-- vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
-- vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
-- vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})



M = { n = {
	["<leader>ff"] = { "<cmd> Telescope find_files <CR>", "Find on filesystem" },
	["<leader>fb"] = { "<cmd> Telescope buffers <CR>", "Find in buffers" },
	["<leader>fg"] = { "<cmd> Telescope live_grep <CR>", "Live grep" }
} }


return M
