-- Options and keys shared by every Jira view. The view-specific keys are set by
-- the module that draws the buffer, because only it knows what a line means.
--
-- The filetype is `jira` rather than `markdown` so that this file exists at all,
-- and so a colourscheme or a plugin can target the views. Markdown is still what
-- the text is, so the markdown parser is started by hand below.
if vim.b.qss_jira_ftplugin then
    return
end
vim.b.qss_jira_ftplugin = true

local buffer = vim.api.nvim_get_current_buf()

vim.bo[buffer].commentstring = ''
vim.bo[buffer].textwidth = 0
vim.wo.wrap = false
vim.wo.list = false
vim.wo.spell = false

-- `gf` on a bare LIS-1234 opens it, because the address it resolves to is the
-- one the BufReadCmd answers.
vim.bo[buffer].includeexpr = "v:lua.require'qss_nvim.jira.protocol'.resolve(v:fname)"
-- isfname is a window-and-global option, not a buffer one, so a colon and a
-- slash have to be allowed for `gf` to see `jira://LIS-1234` as one word.
vim.opt_local.isfname:append({ ':', '/' })

-- A Jira view holds markdown, so it is parsed as markdown. Failing is fine: the
-- text is still readable, only plainer.
pcall(vim.treesitter.start, buffer, 'markdown')

vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buffer, { force = true })
end, { buffer = buffer, desc = 'Close this Jira view' })

vim.b.undo_ftplugin = 'setlocal commentstring< textwidth< includeexpr< isfname<'
