local opts = require("qss_nvim.rust-tools.config")

local M = {
	"simrat39/rust-tools.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"mfussenegger/nvim-dap"
	},
	opts = opts
	-- TODO : Add a function to "enable" conditionnally the plugin, or use the "ft" property ?
}

return {}
