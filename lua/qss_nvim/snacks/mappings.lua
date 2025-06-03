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
    }
}

return M
