return {
    "p00f/clangd_extensions.nvim",
    config = function()
        settings = require('qss_nvim.clang-extensions.settings')
        require('clangd_extensions').setup(settings)
    end
}
