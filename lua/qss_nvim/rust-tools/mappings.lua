require("qss_nvim.nvim-dap.default_mappings")

--vim.cmd('source ' .. nvimrc .. '/lua/qss_nvim/rust-tools/commands.vim')

M = {
    n = {
        --        ["<leader>h"] = { require('rust-tools').hover_range.hover_range, "Display Rust Hover Actions" },
        ["<leader>oc"] = { require('rust-tools').open_cargo_toml.open_cargo_toml, "Open Cargo.toml" },
    }
}

return M
