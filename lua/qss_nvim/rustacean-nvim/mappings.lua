require("qss_nvim.nvim-dap.default_mappings")

local isRustaceanEnabled = function()
    return vim.cmd.RustLsp ~= nil
end

M = {
    n = {
        ["<leader>oc"] = { function()
            if not isRustaceanEnabled() then
                vim.notify "Rustacean not enabled"
                return
            end
            vim.cmd.RustLsp('openCargo')
        end
        , "Open Cargo.toml" },
        ["<leader>cag"] = {
            function()
                if not isRustaceanEnabled() then
                    vim.notify "Rustacean not enabled"
                    return
                end
                local bufnr = vim.api.nvim_get_current_buf()
                vim.cmd.RustLsp('codeAction') -- supports rust-analyzer's grouping
                --{ silent = true, buffer = bufnr }
                -- or vim.lsp.buf.codeAction() if you don't want grouping.
            end,
            "Display code action group" },
        ['<leader>h'] = { function()
            if not isRustaceanEnabled() then
                vim.notify "Rustacean not enabled"
                return
            end
            vim.cmd.RustLsp { 'hover', 'actions' }
            vim.cmd.RustLsp { 'hover', 'actions' }
        end,
            "Rust Hover actions"
        },
        ['<leader>snd'] = { function()
            if not isRustaceanEnabled() then
                vim.notify "Rustacean not enabled"
                return
            end
            vim.cmd.RustLsp({ "renderDiagnostic", cycle })
            vim.cmd.RustLsp({ "renderDiagnostic", current })
        end
        }
    }

}

return M
