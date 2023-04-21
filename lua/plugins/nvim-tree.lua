return {
    "nvim-tree/nvim-tree.lua",
    version = "*",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
    opts = function()
      return require "qss_nvim.nvim-tree.config"
    end,
    config = function(_, opts)
      -- dofile(vim.g.base46_cache .. "nvimtree")
      require("qss_nvim.nvim-tree")-- opts)
      vim.g.nvimtree_side = opts.view.side
    end,
  }
