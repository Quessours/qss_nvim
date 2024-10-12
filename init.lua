vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.rtp:prepend("/home/maxime/98_test_nvim_plugins")
--hello_world = require("hello_world").hello


mappings = require("qss_nvim.mappings")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

vim.filetype.add({
    extension = {
        qml = 'qml'
    }
})

require("lazy").setup("plugins")


--vim.cmd("set relativenumber")
local options = require("qss_nvim.config.options")
for k, v in pairs(options) do
    vim.opt[k] = v
end


qss_utils = require("qss_nvim.utils")
qss_dap_utils = require("qss_nvim.nvim-dap.utils")
