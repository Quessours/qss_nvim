M = {
    n = {
        ["<TAB>"] = { "<cmd> BufferNext<CR>", "Go to next tab" },
        ["<S-TAB>"] = { "<cmd> BufferPrevious<CR>", "Go to previous tab" },
        ["<leader>cot"] = { "<cmd> BufferCloseAllButCurrent<CR>", "Close all other tabs" },
        ["<leader>crt"] = { "<cmd> BufferCloseBuffersRight<CR>", "Close tabs on the right" },
        ["<leader>clt"] = { "<cmd> BufferCloseBuffersLeft<CR>", "Close tabs on the left" },
        ["<leader>cut"] = { "<cmd> BufferCloseAllButCurrentOrPinned<CR>", "Close unpinned tabs" },
        ["<leader>st"] = { "<cmd> BufferPick<CR>", "Select tab ?" },
        ["<leader>pt"] = { "<cmd> BufferPin<CR>", "Pin/unpin tab ?" },
    }
}

return M
