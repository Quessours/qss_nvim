local luals_config = require("lsp.configs.luals")
local clangd_config = require("lsp.configs.clangd")

local lspconfig = require('lspconfig')

lspconfig.lua_ls.setup(luals_config)
lspconfig.clangd.setup(clangd_config)

vim.lsp.enable('luals')
vim.lsp.enable('clangd')
vim.lsp.enable('zls')
