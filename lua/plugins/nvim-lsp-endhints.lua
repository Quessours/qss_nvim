return {
    "Quessours/nvim-lsp-endhints",
    event = "LspAttach",
    branch = "feature/make-render-line-parametrizable ",
    opts = {}, -- required, even if empty
    init = function()
        local rust_endhint = require('qss_nvim.custom_inlay_hints_handler.rust')
        local endhints = require("lsp-endhints")
        endhints.setRefreshHandlersTable({ ["rust"] = rust_endhint.refreshHandler })
        local current_lsp_name = "rust"
        vim.notify(current_lsp_name)
        endhints.enable(current_lsp_name)
    end
}
