-- https://github.com/civitasv/cmake-tools.nvim
--
-- Configure / build / run / debug a CMake project from inside nvim, with
-- CMakePresets, kits and variants understood natively.
return {
    "Civitasv/cmake-tools.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cond = function()
        local util = require("qss_nvim.utils")

        -- isn't there some more idiomatic way to loop on things in LUA ?
        for _, f in pairs(util.scan_dir()) do
            if f == "CMakeLists.txt" or f == "CMakePresets.json" then
                return true
            end
        end
        return false
    end,
    event = "VeryLazy",
    -- qssoverseer-tools.nvim adds the overseer executor and runner, and the
    -- hooks that connect cmake-tools.nvim to it, to the options below.
    config = function(_, opts)
        require("qssoverseer_tools.cmake").setup_cmake_tools(opts)
    end,
    opts = {
        cmake_generate_options = {
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=1",
            "-DQT_QML_GENERATE_QMLLS_INI=ON",
        },
    },
}
