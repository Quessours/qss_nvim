-- In a commit message, <leader>jk inserts the Jira issue key of the branch
-- again, after an edit removed the prefix that qssjira.nvim wrote.
vim.keymap.set('n', '<leader>jk', '<Plug>(JiraInsertKey)', { buffer = true, desc = 'Insert the Jira issue key' })
