return {
    'stevearc/overseer.nvim',
    event = 'VeryLazy',
    opts = {
        component_aliases = {
            default = {
                'on_exit_set_status',
                'on_complete_notify',
                { 'on_complete_dispose', require_view = { 'SUCCESS', 'FAILURE' } },
                { 'on_output_quickfix',  open_on_exit = 'failure',               open_height = 12 },
            },
        },
    },
    config = function(_, opts)
        require('overseer').setup(opts)
        require('qss_nvim.overseer')
    end,
}
