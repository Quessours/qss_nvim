-- preview.nvim comes from a fork on GitLab with the full upstream history. The
-- clone in ~/dev/preview.nvim has the itaranto repository as its upstream remote.
return {
    url = 'git@gitlab.com:Quessours/preview.nvim.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/preview.nvim.
    -- dir = '~/dev/preview.nvim',
    name = 'preview.nvim',
    version = '*',
    opts = {
        -- Your options.
        previewers_by_ft =
        {
            plantuml = {
                name = 'plantuml_text',
                renderer = { type = 'buffer', opts = { split_cmd = 'vsplit' } },
            },
        },
        previewers =
        {
            plantuml = {
                name = 'plantuml_text',
                renderer = { type = 'buffer', opts = { split_cmd = 'split' } },
            },
        },
        render_on_write = true
    },
}
