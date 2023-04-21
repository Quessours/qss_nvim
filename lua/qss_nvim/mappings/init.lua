vim.g.mapleader = " "


local mappings = {}

mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.nvim-tree.mappings")) 

return mappings
