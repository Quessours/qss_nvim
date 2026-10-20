return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  opts = function()
    return require("qss_nvim.nvim-tree.config")
  end,
}
