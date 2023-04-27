return {
	'mfussenegger/nvim-dap',
	event = "BufReadPre",
	dependencies = {
		"theHamsta/nvim-dap-virtual-text",
		"rcarriga/nvim-dap-ui",
		"nvim-telescope/telescope-dap.nvim",
		"jbyuki/one-small-step-for-vimkind",
		"mfussenegger/nvim-dap-python",
	},
	config = function()
		require('qss_nvim.nvim-dap').setup()
		--require('qss_nvim.nvim-dap.adapters')
	end
}
