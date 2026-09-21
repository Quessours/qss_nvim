local M = {
    n = {
        ["<leader>kb"] = { function()
            require("qss_nvim.kas.run").build({})
        end, "kas build" },
        -- The pickers. <leader>kT picks the target to build, <leader>kt the task
        -- to run on one recipe, and both show a second column saying what the
        -- entry is.
        ["<leader>kT"] = { function()
            require("qss_nvim.kas.picker").targets()
        end, "Pick a target to build" },
        ["<leader>kt"] = { function()
            require("qss_nvim.kas.picker").tasks()
        end, "Pick a task to run" },
        ["<leader>kr"] = { function()
            require("qss_nvim.kas.picker").recipes()
        end, "Find a recipe" },
        ["<leader>ks"] = { function()
            require("qss_nvim.kas.run").devshell(
                require("qss_nvim.kas.recipes").owning() or "")
        end, "Devshell for this recipe" },
        ["<leader>kk"] = { function()
            require("qss_nvim.kas.picker").configs()
        end, "Choose the kas config" },
        ["<leader>k?"] = { "<cmd> KasDoctor <CR>", "kas doctor" },
        ["<leader>kc"] = { "<cmd> KasCheckout <CR>", "kas checkout" },
        ["<leader>kd"] = { "<cmd> KasDump <CR>", "Resolved kas config" },
        ["<leader>kg"] = { "<cmd> KasStatus <CR>", "git status in every layer" },
    }
}

return M
