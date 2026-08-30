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
    opts = {
        cmake_generate_options = {
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=1",
            "-DQT_QML_GENERATE_QMLLS_INI=ON",
        },
        cmake_executor = {
            name = "overseer",
            opts = {
                new_task_opts = { strategy = "jobstart" },
                on_new_task = function() end,
            },
        },
        cmake_runner = { name = "terminal" },
    },
}
