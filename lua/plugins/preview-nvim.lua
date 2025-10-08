return {
    'https://gitlab.com/itaranto/preview.nvim',
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
