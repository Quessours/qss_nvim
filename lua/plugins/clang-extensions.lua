return {
    "p00f/clangd_extensions.nvim",
    cond = function()
        local dir_content = require("qss_nvim.utils").scan_dir()

        for _, f in pairs(dir_content) do
            if require("qss_nvim.utils").ends_with(f, "pro") or require("qss_nvim.utils").ends_with(f, "CMakeLists.txt") then
                return true
            end
        end
        return false
    end,
    config = function()
        local settings = require('qss_nvim.clang-extensions.settings')
        require('clangd_extensions').setup(settings)
    end
}
