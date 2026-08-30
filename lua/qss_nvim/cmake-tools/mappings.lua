M = {
    n = {
        ["<leader>mg"] = { "<cmd> CMakeGenerate <CR>", "CMake configure" },
        ["<leader>mb"] = { "<cmd> CMakeBuildChecked <CR>", "CMake build (checked)" },
        ["<leader>m?"] = { "<cmd> CMakeDoctor <CR>", "CMake doctor" },
        ["<leader>mr"] = { "<cmd> CMakeRun <CR>", "CMake run" },
        ["<leader>md"] = { "<cmd> CMakeDebug <CR>", "CMake debug" },
        ["<leader>mc"] = { "<cmd> CMakeClean <CR>", "CMake clean" },
        ["<leader>mt"] = { "<cmd> CMakeSelectBuildTarget <CR>", "Select build target" },
        ["<leader>ml"] = { "<cmd> CMakeSelectLaunchTarget <CR>", "Select launch target" },
        ["<leader>mp"] = { "<cmd> CMakeSelectConfigurePreset <CR>", "Select configure preset" },
        ["<leader>mP"] = { "<cmd> CMakeSelectBuildPreset <CR>", "Select build preset" },
        ["<leader>ms"] = { "<cmd> CMakeSettings <CR>", "CMake settings" },
    }
}

return M
