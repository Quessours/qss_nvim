-- In an Octo review, a FileEntry records the ids of the two diff windows only
-- when it creates its buffers. When a diff window closes, for example after
-- `:q` in a comment buffer, octo opens a new window, but the FileEntry of the
-- current file keeps the id of the closed window. The next comment then fails
-- with "Cannot find diff window <id>".
--
-- setup() wraps FileEntry:get_win and FileEntry:get_alternative_win. When the
-- FileEntry is the current file of the current review, the wrappers copy the
-- window ids of the review layout into the FileEntry first.
--
-- With use_local_fs, octo calls update_layout_for_current_file on each
-- BufEnter. When `:wq` closes a diff window, BufEnter fires in the next window
-- while Neovim still closes the diff window. octo then splits a window to
-- rebuild the layout, and Neovim refuses the split with E242. setup() delays
-- update_layout_for_current_file until the close is complete.
--
-- update_layout_for_current_file reloads the diff, and the reload runs
-- `:doautocmd BufEnter`, which calls update_layout_for_current_file again. If
-- each call scheduled a new update, the updates would never stop and would
-- move the cursor back on each event loop tick. So the delayed update ignores
-- the BufEnter events that it causes, and calls that arrive before the delayed
-- update runs share the same delayed update.
local M = {}

local function defer_layout_update()
    local octo = require('octo')
    local update = octo.update_layout_for_current_file
    if type(update) ~= 'function' then
        vim.notify('octo.nvim has no update_layout_for_current_file any more:'
            .. ' `:wq` in a review comment can fail with E242', vim.log.levels.WARN)
        return
    end
    local scheduled = false
    local running = false
    octo.update_layout_for_current_file = function()
        if scheduled or running then
            return
        end
        scheduled = true
        vim.schedule(function()
            scheduled = false
            running = true
            local ok, err = pcall(update)
            running = false
            if not ok then
                error(err, 0)
            end
        end)
    end
end

function M.setup()
    defer_layout_update()
    local FileEntry = require('octo.reviews.file-entry').FileEntry
    for _, name in ipairs({ 'get_win', 'get_alternative_win' }) do
        local original = FileEntry[name]
        if type(original) ~= 'function' then
            vim.notify('octo.nvim has no FileEntry:' .. name .. ' any more:'
                .. ' a closed diff window can still break review comments', vim.log.levels.WARN)
            return
        end
        FileEntry[name] = function(self, split)
            local layout = require('octo.reviews').get_current_layout()
            if layout and layout:get_current_file() == self then
                self.left_winid = layout.left_winid
                self.right_winid = layout.right_winid
            end
            return original(self, split)
        end
    end
end

return M
