-- gitsigns owns the hunks: navigation, staging and resetting from the buffer,
-- and the hunk textobject. Blame of the current line stays on <leader>gb with
-- snacks, and conflict resolution on <leader>gc with git-conflict.
--
-- Every action is required inside its own mapping because this table is built
-- in init.lua before lazy has loaded a single plugin.
local function gitsigns()
    return require('gitsigns')
end

--- The lines a visual selection covers, in the form the stage and reset actions
--- read a range in.
---@return integer[]
local function selected_range()
    return { vim.fn.line('.'), vim.fn.line('v') }
end

local M = {
    n = {
        ["]h"] = { function() gitsigns().nav_hunk('next') end, "Go to next hunk" },
        ["[h"] = { function() gitsigns().nav_hunk('prev') end, "Go to previous hunk" },

        ["<leader>ghs"] = { function() gitsigns().stage_hunk() end, "Stage hunk" },
        ["<leader>ghr"] = { function() gitsigns().reset_hunk() end, "Reset hunk" },
        ["<leader>ghu"] = { function() gitsigns().undo_stage_hunk() end, "Undo stage hunk" },
        ["<leader>ghS"] = { function() gitsigns().stage_buffer() end, "Stage buffer" },
        ["<leader>ghR"] = { function() gitsigns().reset_buffer() end, "Reset buffer" },
        ["<leader>ghp"] = { function() gitsigns().preview_hunk() end, "Preview hunk" },
        ["<leader>ghi"] = { function() gitsigns().preview_hunk_inline() end, "Preview hunk in the buffer" },
        ["<leader>ghd"] = { function() gitsigns().diffthis() end, "Diff against the index" },
        ["<leader>ghD"] = { function() gitsigns().diffthis('~') end, "Diff against the last commit" },
        ["<leader>ghq"] = { function() gitsigns().setqflist('all') end, "Send every hunk to the quickfix list" },
        ["<leader>ghl"] = { function() gitsigns().toggle_current_line_blame() end, "Toggle inline blame" },
    },
    x = {
        ["<leader>ghs"] = { function() gitsigns().stage_hunk(selected_range()) end, "Stage selected lines" },
        ["<leader>ghr"] = { function() gitsigns().reset_hunk(selected_range()) end, "Reset selected lines" },
        -- select_hunk switches to visual mode, which a <Cmd> mapping is not
        -- allowed to do, so both textobjects go through the command line.
        ["ih"] = { ":<C-U>Gitsigns select_hunk<CR>", "Hunk" },
    },
    o = {
        ["ih"] = { ":<C-U>Gitsigns select_hunk<CR>", "Hunk" },
    },
}

return M
