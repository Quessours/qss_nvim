-- In an Octo review, the toggle_viewed key (<localleader><Space>) that marks a
-- file as viewed also opens the next file of the list. When the key removes the
-- mark, the review stays on the file. On the last file of the list, the review
-- stays on the file too.
--
-- octo.nvim looks up the action of each review key in the octo.mappings table
-- when it sets up a review buffer, so setup() replaces the toggle_viewed
-- action of that table.
local M = {}

function M.setup()
    local actions = require('octo.mappings')
    local toggle_viewed = actions.toggle_viewed
    if type(toggle_viewed) ~= 'function' then
        vim.notify('octo.nvim has no toggle_viewed action any more:'
            .. ' marking a file as viewed does not open the next file', vim.log.levels.WARN)
        return
    end
    actions.toggle_viewed = function()
        local layout = require('octo.reviews').get_current_layout()
        -- The octo action toggles the file under the cursor of the file panel,
        -- which is not always the file that the diff shows.
        local file = layout and layout.file_panel:get_file_at_cursor()
        local marks_viewed = file and file.viewed_state ~= 'VIEWED'
        toggle_viewed()
        if not marks_viewed then
            return
        end
        local index = vim.iter(ipairs(layout.files)):find(function(_, entry)
            return entry == file
        end)
        local next_file = index and layout.files[index + 1]
        if next_file then
            layout:set_current_file(next_file)
        end
    end
end

return M
