vim.g.mapleader = " "


local mappings = {}

mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.nvim-tree.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.telescope.mappings"))
--mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.bufferline.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.barbar-nvim.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.nvim-lspconfig.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.symbols-outline.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.hex-nvim.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.mappings.core"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.snacks.mappings"))

require('qss_nvim.utils').apply_mappings(mappings)
