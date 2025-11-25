return {
    "Quessours/nvim-lsp-endhints",
    event = "LspAttach",
    branch = 'feature/make-inlay-hints-handler-customizable',
    opts = {}, -- required, even if empty
    config = function()
        local endhints = require("lsp-endhints")
        endhints.setRefreshHandlersTable({})
    end
}
