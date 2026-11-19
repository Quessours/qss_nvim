-- qssjira.nvim, the Jira plugin extracted from this configuration into its own
-- GitLab repository. The keys live in qss_nvim/qssjira-nvim/mappings.lua next to
-- every other mapping.
--
-- Not lazy: plugin/qssjira.lua must register the jira:// buffer names and the
-- commit message prefill at startup, and it requires no module until one of
-- them is used.
return {
    url = 'git@gitlab.com:Quessours/qssjira.nvim.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/qssjira.nvim.
    -- dir = '~/dev/qssjira.nvim',
    name = 'qssjira.nvim',
    lazy = false,
    dependencies = { 'folke/snacks.nvim' },
    ---@type qssjira.Options
    opts = {
        issue = {
            hidden_fields = {
                'Projet Commerce',
                'Rank',
                'Development',
                'Atlassian Project',
                'Checklist Progress',
                'Checklist Progress %',
                'Checklist Text',
                'Checklist Text (view-only)',
                'Checklist Content YAML',
                'Checklist Completed',
                'Request Type',
                'Request language',
                'Request participants',
                'Organizations',
                'Satisfaction',
                'Satisfaction date',
                'Approvals',
                'Vulnerability',
                'Issue color',
            },
        },
        create = {
            LIS = {
                defaults = {
                    customfield_11912 = 'Feature',
                    reporter = 'me',
                },
                order = { 'summary', 'customfield_11912', 'description', 'customfield_10006', 'timetracking' },
                hidden = { 'attachment', 'customfield_13141' },
                after_create = {
                    'customfield_10005',    -- Sprint
                    'assignee',
                    'customfield_10002',    -- Dev days
                    'timetracking',         -- Original and remaining estimate
                },
                -- On LIS, an automation rule writes a form over the
                -- description of each new bug.
                follow_automation = true,
            },
        },
        time = {
            -- Tempo reports 25200 seconds for a working day of this account.
            daily_hours = 7,
            -- On this site, an issue estimated at 1d holds 25200 seconds.
            day_hours = {
                ['https://tea-ebook.atlassian.net'] = 7,
            },
        },
    },
}
