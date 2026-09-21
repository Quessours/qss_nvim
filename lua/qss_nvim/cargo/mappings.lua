-- The test keys of the Rust workflow, laid out to match the cmake ones under
-- <leader>m so that merging the two prefixes later is mechanical.
local M = {
    n = {
        -- Picks tests like the cmake <leader>mT does, and runs them in overseer.
        ["<leader>rt"] = { function()
            require("qss_nvim.cargo.tests").pick()
        end, "Run tests" },
        ["<leader>ra"] = { function()
            require("qss_nvim.cargo.tests").run_all()
        end, "Run all tests" },
        ["<leader>rf"] = { function()
            require("qss_nvim.cargo.tests").failures()
        end, "Jump to a failing test" },
        -- Also bound to gd inside the nextest output buffer itself.
        ["<leader>rj"] = { function()
            require("qss_nvim.cargo.tests").goto_under_cursor()
        end, "Go to the test named on this line" },
    }
}

return M
