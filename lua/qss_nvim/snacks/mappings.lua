local picker = require("qss_nvim.snacks.picker")

M = {
    n = {
        ["<leader>dm"] = { function()
            if Snacks.dim.enabled then
                Snacks.dim.disable()
            else
                Snacks.dim.enable()
            end
        end
        , "Toggle dim" },
        ["<leader>zm"] = { function()
            Snacks.zen()
        end
        , "Toggle zen mode" },
        ["<leader>gb"] = { function()
            Snacks.git.blame_line()
        end
        , "Toggle zen mode" },

        -- Pickers. <leader>f is find; the LSP-backed ones live in
        -- qss_nvim/nvim-lspconfig/mappings.lua next to the rest of the LSP keys.
        ["<leader>ff"] = { function() Snacks.picker.files() end, "Find on filesystem" },
        ["<leader>fb"] = { function() Snacks.picker.buffers() end, "Find in buffers" },
        -- Open buffers, recent files and a file search in one list, ranked by
        -- frecency. Deliberately a separate key from <leader>ff, which stays a
        -- plain file list.
        ["<leader>fa"] = { function() Snacks.picker.smart() end, "Find anything" },
        ["<leader>fg"] = { function() Snacks.picker.grep() end, "Live grep" },
        ["<leader>fS"] = { function()
            -- rg takes the last of --smart-case/--case-sensitive, so this wins
            -- over the --smart-case snacks passes by default.
            Snacks.picker.grep({ args = { "--case-sensitive", "--word-regexp" } })
        end, "Strict grep (whole words+case sensitive)" },
        ["<leader>fs"] = { function() Snacks.picker.grep_word() end, "grep string under cursor" },
        ["<leader>fG"] = { picker.grep_filetype, "Grep current filetype only" },
        ["<leader>fk"] = { picker.bookmarks, "Find in bookmarks" },
        ["<leader>fh"] = { function() Snacks.picker.highlights() end, "Find in highlights" },
        ["<leader>fd"] = { function() Snacks.picker.diagnostics() end, "Find in diagnostics" },
        ["<leader>fp"] = { function() Snacks.picker.resume() end, "Reopen previous picker" },
        ["<C-F2>"] = { function() Snacks.picker.recent() end, "Find in files history" },
    }
}

return M
