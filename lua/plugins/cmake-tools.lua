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
    config = function(_, opts)
        require("cmake-tools").setup(opts)
        require("qss_nvim.cmake-tools.session").track()
        require("qss_nvim.cmake-tools.run_env").register_dap_listener()
    end,
    opts = {
        cmake_dap_configuration = {
            [require("qss_nvim.cmake-tools.run_env").DAP_MARKER] = true,
        },
        cmake_generate_options = {
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=1",
            "-DQT_QML_GENERATE_QMLLS_INI=ON",
        },
        cmake_executor = {
            name = "overseer",
            opts = {
                new_task_opts = {
                    strategy = require("qss_nvim.overseer.strategy").build,
                },
                -- Here to ensure that compile output goes into diagnostics,
                -- and that the end of each task is announced
                on_new_task = function(task)
                    require("qss_nvim.cmake-tools.diagnostics").attach(task)
                    require("qss_nvim.cmake-tools.notify").attach(task)
                end,
            },
        },
        cmake_runner = {
            name = "overseer",
            opts = {
                new_task_opts = {
                    strategy = require("qss_nvim.overseer.strategy").program,
                },
                on_new_task = function(task)
                    require("qss_nvim.cmake-tools.run_env").attach(task)
                    require("overseer").open({ enter = false })
                end,
            },
        },
    },
}
