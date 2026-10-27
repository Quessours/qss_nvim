local ensure_installed = {
    "codelldb",
    "rust-analyzer",
    -- The linters qss_nvim.nvim-lint asks for.
    "cmakelint",
    "ruff",
    "oelint-adv",
    -- The servers lsp.lsp_init enables that mason has to fetch.
    "language-server-bitbake",
    "yaml-language-server",
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
    event = "VeryLazy",
    build = function()
        pcall(vim.cmd.MasonUpdate)
    end,
    -- A file opened from the command line starts its server before VeryLazy,
    -- so the mason bin directory goes on PATH here, without loading mason.
    -- setup() is then told to leave PATH alone.
    init = function()
        local bin = vim.fn.stdpath("data") .. "/mason/bin"
        vim.env.PATH = bin .. ":" .. vim.env.PATH
    end,
    config = function()
        require("mason").setup({ PATH = "skip" })
        install_missing()
    end,
}
