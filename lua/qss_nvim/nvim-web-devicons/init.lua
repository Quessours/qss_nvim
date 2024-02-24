local M = {}
function M.setup()
    local config = require("qss_nvim.nvim-web-devicons.config").config
    require("nvim-web-devicons").setup(config)
end

return M
