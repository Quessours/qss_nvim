M = {
    n = {
        ["<leader>mg"] = { "<cmd> CMakeGenerate <CR>", "CMake configure" },
        ["<leader>mb"] = { "<cmd> CMakeBuildChecked <CR>", "CMake build (checked)" },
        ["<leader>mB"] = { "<cmd> CMakeBuildChecked clean <CR>", "CMake clean build (keeps cache)" },
        ["<leader>mR"] = { "<cmd> CMakeRebuild <CR>", "CMake clean rebuild (wipes build dir)" },
        ["<leader>m?"] = { "<cmd> CMakeDoctor <CR>", "CMake doctor" },
        ["<leader>mr"] = { "<cmd> CMakeRun <CR>", "CMake run" },
        ["<leader>md"] = { "<cmd> CMakeDebug <CR>", "CMake debug" },
        ["<leader>mc"] = { "<cmd> CMakeClean <CR>", "CMake clean" },
        -- Picks tests like :CMakeRunTest but runs them in overseer rather than
        -- the terminal the cmake_runner would use. The "cmake test" task on
        -- <leader>mm is the non-interactive one, taking a preset and a filter.
        ["<leader>mT"] = { function()
            require("qss_nvim.cmake-tools.tests").pick()
        end, "Run tests" },
        -- Also bound to gd inside the ctest output buffer itself.
        ["<leader>mj"] = { function()
            require("qss_nvim.cmake-tools.tests").goto_under_cursor()
        end, "Go to the test named on this line" },
        ["<leader>ma"] = { function()
            require("qss_nvim.cmake-tools.tests").run_all()
        end, "Run all tests" },
        ["<leader>mf"] = { function()
            require("qss_nvim.cmake-tools.tests").failures()
        end, "Jump to a failing test" },
        ["<leader>mt"] = { "<cmd> CMakeSelectBuildTarget <CR>", "Select build target" },
        ["<leader>ml"] = { "<cmd> CMakeSelectLaunchTarget <CR>", "Select launch target" },
        -- The same picker in the debug namespace, since it is what <leader>dc
        -- resolves its program from. <leader>dC is nvim-dap's conditional
        -- breakpoint.
        ["<leader>dl"] = { "<cmd> CMakeSelectLaunchTarget <CR>", "Select launch target" },
        ["<leader>mp"] = { "<cmd> CMakeSelectConfigurePreset <CR>", "Select configure preset" },
        ["<leader>mP"] = { "<cmd> CMakeSelectBuildPreset <CR>", "Select build preset" },
        ["<leader>ms"] = { "<cmd> CMakeSettings <CR>", "CMake settings" },
    }
}

return M
