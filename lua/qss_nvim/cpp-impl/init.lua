local generate = require('qss_nvim.cpp-impl.generate')

local M = {}

M.run = generate.run

vim.api.nvim_create_user_command('CppImplement', function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    generate.run(vim.api.nvim_get_current_buf(), row)
end, { desc = 'Implement the declaration under the cursor in the matching source file' })

return M
