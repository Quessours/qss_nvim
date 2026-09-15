-- noice replaces the cmdline, the message area, the popupmenu and vim.notify
-- with its own views. It takes vim.notify over, so every notification arrives
-- here as an `event = "notify"` message and passes through the routes below.
--
-- Rendering still belongs to snacks: the `notify` view lists `snacks` first in
-- its backend chain (noice/config/views.lua:67), and noice/view/backend/
-- snacks.lua:26 accepts it while Snacks.config.notifier.enabled is true. So the
-- snacks notifier must stay on, and its timeout of 3000 is what dismisses a
-- notification. `:Noice` opens the history.
--
-- cmdheight is already 0 in qss_nvim/config/options.lua, which is the value
-- noice expects.
return {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = {
        -- hard dependency: noice draws every view with nui
        'MunifTanjim/nui.nvim',
    },
    opts = {
        lsp = {
            override = {
                -- the cmp entry override rewrites the markdown inside the
                -- documentation window of qss_nvim/nvim-cmp/init.lua. The
                -- CmpDocBorder border set there is kept.
                ['cmp.entry.get_documentation'] = true,
                ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
                ['vim.lsp.util.stylize_markdown'] = true,
            },
            -- no $/progress handler exists in lua/lsp, so this adds progress
            -- reporting instead of competing with one
            progress = { enabled = true },
            hover = { enabled = true },
            signature = { enabled = true },
        },
        presets = {
            bottom_search = true,
            command_palette = true,
            lsp_doc_border = true,
        },
        routes = {
            -- format_on_save is on for clangd, qmlls and rust-analyzer, so the
            -- write message appears on every save
            {
                filter = { event = 'msg_show', kind = '', find = 'written' },
                opts = { skip = true },
            },
            {
                filter = { event = 'msg_show', kind = 'search_count' },
                opts = { skip = true },
            },
            -- the line and byte count of a read file
            {
                filter = { event = 'msg_show', find = '%d+L, %d+B' },
                view = 'mini',
            },

            -- the long_message_to_split preset sends this same filter to
            -- `cmdline_output`, which inherits the split view and stays until
            -- `q`. The preset is off, and mini takes the message instead:
            -- 2000 ms, then gone. mini clips at 10 lines
            -- (noice/config/views.lua:181), so `:Noice` holds the full text.
            {
                filter = { event = 'msg_show', min_height = 20 },
                view = 'mini',
            },
            -- hover on a symbol the server knows nothing about
            {
                filter = { event = 'notify', find = 'No information available' },
                opts = { skip = true },
            },

            -- Overseer. on_complete_notify formats "<STATUS> <task name>"
            -- (on_complete_notify.lua:53), and the rust dap configurations run
            -- `cargo build` as a preLaunchTask, so a successful launch reports
            -- twice. FAILURE, CANCELED and the "DAP preLaunchTask '...' failed"
            -- error of overseer/dap.lua:57 carry no route and stay visible.
            {
                filter = { event = 'notify', find = '^SUCCESS ' },
                opts = { skip = true },
            },

            -- cmake-tools. Every message of the plugin goes through
            -- cmake-tools/log.lua:4. These two are status remarks that repeat.
            {
                filter = { event = 'notify', find = 'There is no terminal instance' },
                opts = { skip = true },
            },
            {
                -- the misspelling of "terminals" is upstream, at
                -- cmake-tools/terminal.lua:335. Match a part without it.
                filter = { event = 'notify', find = 'may clutter your workspace' },
                view = 'mini',
            },
        },
    },
}
