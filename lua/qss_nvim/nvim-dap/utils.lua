M = {}



function M.load_launchjson(path)
    local dap = require("dap")
    dap.configurations = {}
    require("dap.ext.vscode").load_launchjs(path, { codelldb = { "c", "cpp" } })
end

return M
