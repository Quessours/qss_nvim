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
    }
}

return M
