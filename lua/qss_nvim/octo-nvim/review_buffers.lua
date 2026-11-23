-- In an Octo review with use_local_fs, the right diff window shows the file
-- from disk, and octo.nvim marks the buffer of that file as listed. barbar
-- shows each listed buffer as a tab, so each file of the review adds a tab.
--
-- setup() wraps the `_create_buffer` function of octo.reviews.file-entry. When
-- the wrapper finds that octo.nvim listed a buffer that was not listed before
-- the call, the wrapper unlists the buffer again. A file that was already open
-- before the review keeps its tab.
local M = {}

function M.setup()
    local file_entry = require('octo.reviews.file-entry')
    local original = file_entry._create_buffer
    if type(original) ~= 'function' then
        vim.notify('octo.nvim has no file-entry._create_buffer any more:'
            .. ' each file of a review can add a barbar tab', vim.log.levels.WARN)
        return
    end
    file_entry._create_buffer = function(opts)
        local existing = opts.use_local and vim.fn.bufnr(opts.path) or -1
        local was_listed = existing ~= -1 and vim.bo[existing].buflisted
        local bufnr = original(opts)
        if opts.use_local and bufnr and not was_listed then
            vim.bo[bufnr].buflisted = false
        end
        return bufnr
    end
end

return M
