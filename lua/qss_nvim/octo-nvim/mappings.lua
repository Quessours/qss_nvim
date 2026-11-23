-- The <leader>go keys of octo.nvim. Each key runs an `:Octo` command, and the
-- first command loads the plugin. The pull request filters come from
-- qss_nvim/octo-nvim/filters.lua. The keys inside an Octo buffer, under
-- <localleader>, come from the plugin itself.
local M = {
    n = {
        ["<leader>goa"] = { "<Cmd>Octo<CR>", "Octo actions" },
        ["<leader>gop"] = { "<Cmd>Octo pr list<CR>", "Pull requests" },
        ["<leader>goP"] = { "<Cmd>Octo pr create<CR>", "Create a pull request" },
        ["<leader>goc"] = { "<Cmd>Octo pr checkout<CR>", "Check out the pull request" },
        ["<leader>goi"] = { "<Cmd>Octo issue list<CR>", "Issues" },
        ["<leader>goI"] = { "<Cmd>Octo issue create<CR>", "Create an issue" },
        ["<leader>goS"] = { "<Cmd>Octo search<CR>", "Search GitHub" },
        ["<leader>gof"] = { function() require("qss_nvim.octo-nvim.filters").pick() end, "Pull request filters" },
        -- While octo.nvim reads subject.url of a CheckSuite notification, which
        -- GitHub sends as null, `:Octo notification list` fails to open.
        -- Restore the key when the plugin skips such notifications.
        -- ["<leader>gon"] = { "<Cmd>Octo notification list<CR>", "Notifications" },
        ["<leader>gor"] = { "<Cmd>Octo review start<CR>", "Start a review" },
        ["<leader>goR"] = { "<Cmd>Octo review resume<CR>", "Resume the review" },
        ["<leader>gos"] = { "<Cmd>Octo review submit<CR>", "Submit the review" },
        ["<leader>gow"] = { "<Cmd>Octo pr browser<CR>", "Web: open the pull request" },
    }
}

-- One key per pull request filter, <leader>go followed by the key of the filter.
for _, filter in ipairs(require("qss_nvim.octo-nvim.filters").list) do
    M.n["<leader>go" .. filter.key] = { filter.run, filter.label }
end

return M
