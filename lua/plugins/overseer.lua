return {
    'stevearc/overseer.nvim',
    event = 'VeryLazy',
    opts = {
        -- Debug configurations build through qss_nvim.overseer.build_first,
        -- so nvim-dap needs no preLaunchTask support.
        dap = false,
        task_list = {
            render = function(task)
                return require('qss_nvim.overseer.render').task(task)
            end,
        },
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
