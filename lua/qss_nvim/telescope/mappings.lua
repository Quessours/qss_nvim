M = {
    n = {
        ["<leader>ff"] = { "<cmd> Telescope find_files <CR>", "Find on filesystem" },
        ["<leader>fb"] = { "<cmd> Telescope buffers <CR>", "Find in buffers" },
        ["<leader>fg"] = { "<cmd> Telescope live_grep <CR>", "Live grep" },
        ["<leader>fk"] = { "<cmd> Telescope bookmarks <CR>", "Find in bookmarks" },
        ["<leader>fh"] = { "<cmd> Telescope highlights <CR>", "Find in highlights" },
        ["<C-F2>"] = { "<cmd> Telescope oldfiles <CR>", "Find in files history" }
    }
}

--  :lua require('telescope.builtin').oldfiles(require('telescope.themes').get_dropdown{
--  previewer = false
-- })

return M
