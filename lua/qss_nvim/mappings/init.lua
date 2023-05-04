vim.g.mapleader = " "


local mappings = {}

mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.nvim-tree.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.telescope.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.bufferline.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.mappings.core"))

require('qss_nvim.utils').apply_mappings(mappings)
