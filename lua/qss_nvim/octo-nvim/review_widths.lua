-- In an Octo review, the left diff window shows the base version of the file.
-- When the pull request adds the file, the base version is empty, so the left
-- window shrinks to ADDED_FILE_LEFT_WIDTH columns and the right window takes
-- the rest. While the left window shows another buffer, for example the
-- comment thread of a line of the right side, or the base version of a file
-- that the pull request changes, the two diff windows share the width.
--
-- octo.nvim has no option for the widths of the diff windows, so setup()
-- adds a BufWinEnter autocommand. Octo puts each file and each comment thread
-- in a diff window with nvim_win_set_buf, which triggers BufWinEnter.
local M = {}

local ADDED_FILE_LEFT_WIDTH = 10

-- The status letter that octo.nvim gives to a file that the pull request adds.
local ADDED = 'A'

---@param layout table The octo.nvim Layout of the current review.
local function resize(layout)
    local left = layout.left_winid
    local right = layout.right_winid
    if not (vim.api.nvim_win_is_valid(left) and vim.api.nvim_win_is_valid(right)) then
        return
    end
    local file = layout:get_current_file()
    local shows_empty_base = file ~= nil and file.status == ADDED
        and vim.api.nvim_win_get_buf(left) == file.left_bufid
    local total = vim.api.nvim_win_get_width(left) + vim.api.nvim_win_get_width(right)
    local left_width = math.floor(total / 2)
    if shows_empty_base then
        left_width = ADDED_FILE_LEFT_WIDTH
    end
    vim.api.nvim_win_set_width(left, left_width)
end

function M.setup()
    vim.api.nvim_create_autocmd('BufWinEnter', {
        group = vim.api.nvim_create_augroup('qss_octo_review_widths', {}),
        desc = 'Shrink the left Octo diff window for an added file',
        callback = function()
            -- Octo sets the buffer of a diff window before it finishes the
            -- review state, so the resize waits for the end of the event.
            vim.schedule(function()
                local layout = require('octo.reviews').get_current_layout()
                if layout then
                    resize(layout)
                end
            end)
        end,
    })
end

return M
