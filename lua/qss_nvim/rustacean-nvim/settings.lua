local opts = {
    tools = {
        -- rustacean-nvim options

        -- callback to execute once rust-analyzer is done initializing the workspace
        -- The callback receives one parameter indicating the `health` of the server: "ok" | "warning" | "error"
        on_initialized = function(status)
            local level = vim.log.levels.INFO
            if status.health ~= 'ok' then
                level = vim.log.levels.WARN
            end
            vim.notify(('rust-analyzer: %s'):format(status.health), level)
        end,
        -- automatically call RustReloadWorkspace when writing to a Cargo.toml file.
        reload_workspace_from_cargo_toml = true,
        float_win_config = {
            auto_focus = true,
            border = {
                { "╭", "FloatBorder" },
                { "─", "FloatBorder" },
                { "╮", "FloatBorder" },
                { "│", "FloatBorder" },
                { "╯", "FloatBorder" },
                { "─", "FloatBorder" },
                { "╰", "FloatBorder" },
                { "│", "FloatBorder" },
            },
        },
        -- settings for showing the crate graph based on graphviz and the dot
        -- command
        crate_graph = {
            -- Backend used for displaying the graph
            -- see: https://graphviz.org/docs/outputs/
            -- default: x11
            backend = "x11",
            -- where to store the output, nil for no output stored (relative
            -- path from pwd)
            -- default: nil
            output = nil,
            -- true for all crates.io and external crates, false only the local
            -- crates
            -- default: true
            full = true,
        },
    },
    server = {
        -- read by the LspAttach hook of lua/qss_nvim/nvim-lspconfig/init.lua
        format_on_save = true,
        default_settings = {
            ['rust-analyzer'] = {
                cargo = { allFeatures = true },
                checkOnSave = true,
            },
        },
        on_attach = function(_, bufnr)
            local apply_mappings = require("qss_nvim.utils").apply_mappings
            local mappings = require("qss_nvim.rustacean-nvim.mappings")
            assert(mappings ~= nil)
            local buffer_local = vim.deepcopy(mappings)
            for _, mode_values in pairs(buffer_local) do
                for _, mapping_info in pairs(mode_values) do
                    mapping_info.opts = vim.tbl_extend("keep", mapping_info.opts or {},
                        { buffer = bufnr })
                end
            end
            apply_mappings(buffer_local)
        end,
    },
}


return opts
