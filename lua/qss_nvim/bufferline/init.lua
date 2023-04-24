vim.opt.termguicolors = true

local bufferline = require("bufferline")

local options = require("qss_nvim.bufferline.config")
local highlights = require("qss_nvim.bufferline.highlights")
bufferline.setup{ options = options, highlights = highlights }
