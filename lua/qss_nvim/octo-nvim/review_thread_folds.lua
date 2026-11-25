-- In an Octo review, when the cursor is on a line with review comments, octo
-- shows the comments in the other diff window. Before octo shows them, octo
-- runs `diffoff!`, which turns off diff mode in each window of the tab. The
-- diff folds of the code window then open, and the visible code jumps. When
-- the cursor leaves the commented lines, octo turns diff mode back on, and the
-- diff folds close again.
--
-- setup() wraps show_review_threads of octo.reviews.thread-panel. When the
-- wrapped call turns off diff mode in the code window, the wrapper creates
-- manual folds at the lines of the closed diff folds and restores the view of
-- the code window.
local M = {}

---@param winid integer
---@return integer[][] # The first and last line of each closed fold.
local function closed_folds(winid)
    return vim.api.nvim_win_call(winid, function()
        local folds = {}
        local last_line = vim.fn.line('$')
        local line = 1
        while line <= last_line do
            local fold_end = vim.fn.foldclosedend(line)
            if fold_end == -1 then
                line = line + 1
            else
                table.insert(folds, { line, fold_end })
                line = fold_end + 1
            end
        end
        return folds
    end)
end

---@param winid integer
---@param folds integer[][]
---@param view vim.fn.winsaveview.ret
local function restore_folds(winid, folds, view)
    vim.api.nvim_win_call(winid, function()
        vim.wo.foldmethod = 'manual'
        vim.wo.foldenable = true
        vim.cmd('normal! zE')
        for _, fold in ipairs(folds) do
            vim.cmd(fold[1] .. ',' .. fold[2] .. 'fold')
        end
        vim.fn.winrestview(view)
    end)
end

function M.setup()
    local thread_panel = require('octo.reviews.thread-panel')
    local original = thread_panel.show_review_threads
    if type(original) ~= 'function' then
        vim.notify('octo.nvim has no thread-panel show_review_threads any more:'
            .. ' review comments unfold the code window again', vim.log.levels.WARN)
        return
    end
    thread_panel.show_review_threads = function(jump_to_buffer)
        local winid = vim.api.nvim_get_current_win()
        if not vim.wo[winid].diff then
            return original(jump_to_buffer)
        end
        local folds = closed_folds(winid)
        local view = vim.api.nvim_win_call(winid, vim.fn.winsaveview)
        original(jump_to_buffer)
        local diff_turned_off = vim.api.nvim_win_is_valid(winid) and not vim.wo[winid].diff
        if diff_turned_off then
            restore_folds(winid, folds, view)
        end
    end
end

return M
