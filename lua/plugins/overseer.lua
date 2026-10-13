return {
    'stevearc/overseer.nvim',
    event = 'VeryLazy',
    opts = {
        component_aliases = {
            default = {
                'on_exit_set_status',
                'on_complete_notify',
                { 'on_complete_dispose', require_view = { 'SUCCESS', 'FAILURE' } },
                -- The log, where <CR> on an error opens its file. Not at
                -- start, which open_output does by default.
                { 'open_output',         on_start = 'never', on_complete = 'failure' },
            },
        },
    },
    config = function(_, opts)
        require('overseer').setup(opts)
        require('qss_nvim.overseer')
    end,
}
