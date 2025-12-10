return {
    "Quessours/nvim-lsp-endhints",
    event = "LspAttach",
    branch = "feature/make-render-line-parametrizable",
    opts = {}, -- required, even if empty
    config = function()
        require("lsp-endhints").setup { label = { truncateAtChars = 2000 } }
    end,

    init = function()
        local rust_endhint = require('qss_nvim.custom_inlay_hints_handler.rust')
        local endhints = require("lsp-endhints")
        endhints.setInlayHintFormatFunction(rust_endhint.formatInlayHints)
        endhints.enable()
    end
}
