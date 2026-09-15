local ensure_installed = {
    "codelldb",
    "rust-analyzer",
    -- The linters qss_nvim.nvim-lint asks for.
    "cmakelint",
    "ruff",
}

local function install_missing()
    local registry = require("mason-registry")

    registry.refresh(function()
        for _, name in ipairs(ensure_installed) do
            if not registry.has_package(name) then
                vim.notify(("mason: unknown package %s"):format(name), vim.log.levels.WARN)
            elseif not registry.is_installed(name) then
                registry.get_package(name):install()
            end
        end
    end)
end

return {
    "mason-org/mason.nvim",
    init = function()
        require("mason").setup()
        install_missing()
    end
}
