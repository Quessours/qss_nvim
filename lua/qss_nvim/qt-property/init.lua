local client_priority = require('qss_nvim.nvim-cmp.client_priority')
local diagnostics = require('qss_nvim.qt-property.diagnostics')
local generate = require('qss_nvim.qt-property.generate')

local M = {}

M.generate = generate.run

vim.api.nvim_create_user_command('QtPropertyGenerate', function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    generate.run(vim.api.nvim_get_current_buf(), row)
end, { desc = 'Generate the members the Q_PROPERTY on this line declares' })

vim.api.nvim_create_user_command('QtPropertyDiagnostics', function()
    diagnostics.toggle()
end, { desc = 'Toggle the Q_PROPERTY diagnostics for this session' })

client_priority.prefer('qtprops')

diagnostics.setup()

return M
