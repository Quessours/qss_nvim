-- Every module here is required inside the mapping, because this table is built
-- in init.lua before lazy has loaded snacks, which every entry point needs.
--
-- The multi-key sequences never sit under a key that is also a mapping of its
-- own: `ja`, `jc`, `jm` and `js` are prefixes and nothing else, so none of them
-- waits out timeoutlen wondering whether another key is coming.
--
-- Editing the description, the summary and the links has no key on purpose. All
-- three are edited with `i` on the line that shows them.
local function actions()
    return require('qss_nvim.jira.actions')
end

local function issue()
    return require('qss_nvim.jira.issue')
end

local function picker()
    return require('qss_nvim.jira.picker')
end

local M = {
    n = {
        -- Views
        ["<leader>jcs"] = { function() require('qss_nvim.jira.board').open() end, "Current sprint board" },
        ["<leader>jS"] = { function() require('qss_nvim.jira.sprint').pick() end, "Show a sprint report" },
        ["<leader>jB"] = { function() require('qss_nvim.jira.board').backlog() end, "Backlog" },
        ["<leader>jmt"] = { function() picker().issues() end, "My tickets in the sprint" },
        ["<leader>jE"] = { function() picker().epics() end, "Epics" },
        ["<leader>jp"] = { function() picker().all_issues() end, "Project issues, unresolved" },
        ["<leader>jT"] = { function() require('qss_nvim.jira.timesheet').open() end, "Timesheet of the week" },

        -- Finding
        ["<leader>jf"] = { function() issue().find(issue().open) end, "Find an issue by key or words" },
        ["<leader>jq"] = { function() picker().ask_jql() end, "Run a JQL query" },
        ["<leader>jQ"] = { function() picker().jql_history() end, "Re-run a JQL query" },
        ["<leader>jv"] = { function() issue().with_key(issue().open) end, "View the issue" },
        ["<leader>jW"] = { function() issue().with_key(actions().open_in_browser) end, "Web: open in the browser" },

        -- Acting on one issue
        ["<leader>jsw"] = { function()
            picker().issues({ on_confirm = function(key)
                require('qss_nvim.jira.work').start(key)
            end })
        end, "Start working on an issue" },
        ["<leader>jmi"] = { function() issue().with_key(picker().transition) end, "Move the issue to another state" },
        ["<leader>jac"] = { function() issue().with_key(actions().add_comment) end, "Add a comment" },
        ["<leader>jat"] = { function() require('qss_nvim.jira').create() end, "Add a ticket" },
        ["<leader>jas"] = { function() issue().with_key(actions().assign) end, "Assign the issue to anyone" },
        ["<leader>jF"] = { function()
            issue().with_key(require('qss_nvim.jira.fields').pick)
        end, "Fields of the issue" },
        ["<leader>jL"] = { function() issue().with_key(actions().edit_labels) end, "Labels of the issue" },
        ["<leader>jw"] = { function() issue().with_key(require('qss_nvim.jira.tempo').log) end, "Work logged in Tempo" },
        ["<leader>jr"] = { function() issue().with_key(issue().open) end, "Reload the issue view" },
    }
}

return M
