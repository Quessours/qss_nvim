-- The <leader>j keys of qssjira.nvim. Each key runs a `:Jira` subcommand, so this
-- table requires no module of the plugin.
--
-- The multi-key sequences never sit under a key that is also a mapping of its
-- own: `ja`, `jc`, `jm` and `js` are prefixes and nothing else, so none of them
-- waits out timeoutlen wondering whether another key is coming.
return {
    n = {
        -- Views
        ["<leader>jcs"] = { "<Cmd>Jira board<CR>", "Current sprint board" },
        ["<leader>jsu"] = { "<Cmd>Jira standup<CR>", "Standup" },
        ["<leader>jS"] = { "<Cmd>Jira sprints<CR>", "Show a sprint report" },
        ["<leader>jB"] = { "<Cmd>Jira backlog<CR>", "Backlog" },
        ["<leader>jmt"] = { "<Cmd>Jira mine<CR>", "My tickets in the sprint" },
        ["<leader>jE"] = { "<Cmd>Jira epics<CR>", "Epics" },
        ["<leader>jp"] = { "<Cmd>Jira project<CR>", "Project issues, unresolved" },
        ["<leader>jT"] = { "<Cmd>Jira week<CR>", "Timesheet of the week" },

        -- Finding
        ["<leader>jf"] = { "<Cmd>Jira find<CR>", "Find an issue by key or words" },
        ["<leader>jq"] = { "<Cmd>Jira jql<CR>", "Run a JQL query" },
        ["<leader>jQ"] = { "<Cmd>Jira jql-history<CR>", "Re-run a JQL query" },
        ["<leader>jl"] = { "<Cmd>Jira filters<CR>", "Saved filters" },
        ["<leader>jv"] = { "<Cmd>Jira view<CR>", "View the issue" },
        ["<leader>jW"] = { "<Cmd>Jira browse<CR>", "Web: open in the browser" },

        -- Acting on one issue
        ["<leader>jsw"] = { "<Cmd>Jira start<CR>", "Start working on an issue" },
        ["<leader>jmi"] = { "<Cmd>Jira transition<CR>", "Move the issue to another state" },
        ["<leader>jac"] = { "<Cmd>Jira comment<CR>", "Add a comment" },
        ["<leader>jat"] = { "<Cmd>Jira create<CR>", "Add a ticket" },
        ["<leader>jas"] = { "<Cmd>Jira assign<CR>", "Assign the issue to anyone" },
        ["<leader>jF"] = { "<Cmd>Jira fields<CR>", "Fields of the issue" },
        ["<leader>jL"] = { "<Cmd>Jira labels<CR>", "Labels of the issue" },
        ["<leader>jw"] = { "<Cmd>Jira log<CR>", "Work logged in Tempo" },
        ["<leader>jr"] = { "<Cmd>Jira view<CR>", "Reload the issue view" },

        -- Projects
        ["<leader>jP"] = { "<Cmd>Jira profile<CR>", "Switch Jira profile" },
    }
}
