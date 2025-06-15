require("qss_nvim.nvim-dap.default_mappings")

M = {
    n = {
        --        ["<leader>h"] = { require('rust-tools').hover_range.hover_range, "Display Rust Hover Actions" },
        ["<leader>oc"] = { function()
            vim.cmd.RustLsp('openCargo')
        end
        , "Open Cargo.toml" },
    }
}

return M
