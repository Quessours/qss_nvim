-- In an Octo review, a FileEntry records the ids of the two diff windows only
-- when it creates its buffers. When a diff window closes, for example after
-- `:q` in a comment buffer, octo opens a new window, but the FileEntry of the
-- current file keeps the id of the closed window. The next comment then fails
-- with "Cannot find diff window <id>".
--
-- setup() wraps FileEntry:get_win and FileEntry:get_alternative_win. When the
-- FileEntry is the current file of the current review, the wrappers copy the
-- window ids of the review layout into the FileEntry first.
local M = {}

function M.setup()
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
