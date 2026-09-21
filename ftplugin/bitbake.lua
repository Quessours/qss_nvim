-- Recipes, bbappends, bbclasses and the layer conf files. Neovim sets the
-- filetype for all four, and ships nothing else for them.
if vim.b.qss_bitbake_ftplugin then
    return
end
vim.b.qss_bitbake_ftplugin = true

local buffer = vim.api.nvim_get_current_buf()

vim.bo[buffer].commentstring = '# %s'
vim.bo[buffer].comments = ':#'

-- Recipe and task completion, for this buffer only.
require('qss_nvim.kas.completion').attach(buffer)

vim.b.undo_ftplugin = 'setlocal commentstring< comments<'
