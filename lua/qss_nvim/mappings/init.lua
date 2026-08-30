vim.g.mapleader = " "


local mappings = {}

mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.nvim-tree.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.barbar-nvim.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.nvim-lspconfig.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.symbols-outline.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.hex-nvim.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.mappings.core"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.snacks.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.git-conflict-nvim.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.cmake-tools.mappings"))
mappings = vim.tbl_deep_extend("force", mappings, require("qss_nvim.overseer.mappings"))

require('qss_nvim.utils').apply_mappings(mappings)
