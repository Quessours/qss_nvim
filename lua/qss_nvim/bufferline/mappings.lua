M = {
    n = {
        ["<TAB>"] = { "<cmd> BufferLineCycleNext <CR>", "Go to next tab" },
        ["<S-TAB>"] = { "<cmd> BufferLineCyclePrev <CR>", "Go to previous tab" },
        ["<leader>ct"] = { "<cmd> BufferLinePickClose <CR>", "Close chosen tab" },
        ["<leader>gt"] = { "<cmd> BufferLinePick <CR>", "Go to tab" },
        ["<leader>cot"] = { "<cmd> BufferLineCloseLeft <CR> <cmd> BufferLineCloseRight <CR>", "Go to tab" },
    }
}

return M
