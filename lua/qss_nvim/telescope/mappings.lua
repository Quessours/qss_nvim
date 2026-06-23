M = {
    n = {
        ["<leader>ff"] = { "<cmd> Telescope find_files <CR>", "Find on filesystem" },
        ["<leader>fb"] = { "<cmd> Telescope buffers <CR>", "Find in buffers" },
        ["<leader>fg"] = { "<cmd> Telescope live_grep <CR>", "Live grep" },
        ["<leader>fS"] = { function()
            local telescope_builtins = require("telescope.builtin")
            local options = {
                vimgrep_arguments = {
                    "rg",
                    "--color=never",
                    "--no-heading",
                    "--with-filename",
                    "--line-number",
                    "--column",
                    "--case-sensitive",
                    "--word-regexp"
                }
            }
            telescope_builtins.live_grep(
                options)
        end, "Strict grep (whole words+case sensitive)" },
        ["<leader>fs"] = { "<cmd> Telescope grep_string <CR>", "grep string under cursor" },
        ["<leader>fk"] = { "<cmd> Telescope bookmarks <CR>", "Find in bookmarks" },
        ["<leader>fh"] = { "<cmd> Telescope highlights <CR>", "Find in highlights" },
        ["<C-F2>"] = { "<cmd> Telescope oldfiles <CR>", "Find in files history" }
    }
}

--  :lua require('telescope.builtin').oldfiles(require('telescope.themes').get_dropdown{
--  previewer = false
-- })

return M
