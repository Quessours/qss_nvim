return {
    'stevearc/overseer.nvim',
    event = 'VeryLazy',
    dependencies = { 'qssoverseer.nvim', 'qssoverseer-tools.nvim', 'qssoverseer-kas.nvim' },
    opts = {
        -- Debug configurations build through qssoverseer.build_first, so
        -- nvim-dap needs no preLaunchTask support.
        dap = false,
        task_list = {
            render = function(task)
                return require('qssoverseer.render').task(task)
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
        require('qssoverseer').setup({
            log_colors = { qt_message_pattern = true },
            build_failures = {
                -- Tried in this order on each line of a failed ninja step.
                parsers = { 'qmllint', 'compiler', 'error_text' },
            },
        })
        require('qssoverseer_tools').setup({})
        require('qssoverseer_kas').setup({
            -- The kas keys and their which-key group exist only inside a kas
            -- project, like the :Kas* commands.
            on_project = function()
                require('qss_nvim.utils').apply_mappings(require('qss_nvim.kas.mappings'))
                require('which-key').add({ { '<leader>k', group = 'kas' } })
            end,
        })
        require('qss_nvim.overseer')
    end,
}
