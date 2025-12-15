return {
    "chrisgrieser/nvim-lsp-endhints",
    event = "LspAttach",
    branch = "main",
    opts = {},
    config = function()
        require("lsp-endhints").setup { label = { truncateAtChars = 2000 },
            hintFormatFunc = function(hints, bufnr, defaultHintFormatFunc)
                if vim.bo[bufnr].filetype == "rust" then
                    return require('qss_nvim.custom_inlay_hints_handler.rust').formatInlayHints(hints)
                end
                return defaultHintFormatFunc(hints)
            end
        }
    end,

    init = function()
        local endhints = require("lsp-endhints")
        endhints.enable()
    end
}
