-- try_lint() reads linters_by_ft, so with the table left empty it ran on every
-- write and reported nothing. A filetype belongs here only when no language
-- server already lints it: clangd, luals, pyright, rust-analyzer, zls, ts_ls,
-- sqls, qmlls, fish_lsp and bashls (which calls shellcheck itself) cover the
-- rest.
local lint = require('lint')

lint.linters_by_ft = {
    -- No cmake language server is enabled, so nothing else reads a
    -- CMakeLists.txt, and this config drives cmake through overseer.
    cmake = { 'cmakelint' },
    -- pyright reports type errors only. ruff adds the pyflakes and pycodestyle
    -- rules on top of it.
    python = { 'ruff' },
    -- The bitbake language server reports what it cannot parse. oelint-adv
    -- reports what parses and still breaks the Yocto recipe guidelines.
    bitbake = { 'oelint-adv' },
}

local warned = {}

--- try_lint() spawns the linter command itself and warns when the spawn fails,
--- so a tool mason has not installed yet complains on every single write. Say
--- it once and leave that linter out for the rest of the session.
---@param name string
---@return boolean
local function is_installed(name)
    local linter = lint.linters[name]
    if type(linter) == 'function' then
        linter = linter()
    end

    if vim.fn.executable(linter.cmd) == 1 then
        return true
    end

    if not warned[name] then
        warned[name] = true
        vim.notify(('%s is not installed, so %s does not run'):format(linter.cmd, name),
            vim.log.levels.WARN, { title = 'nvim-lint' })
    end
    return false
end

---@param filetype string
---@return string[]
local function runnable_linters(filetype)
    local names = {}
    for _, name in ipairs(lint.linters_by_ft[filetype] or {}) do
        if is_installed(name) then
            names[#names + 1] = name
        end
    end
    return names
end

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
    group = vim.api.nvim_create_augroup('QssLint', { clear = true }),
    desc = 'Lint the buffer',
    callback = function(event)
        local names = runnable_linters(vim.bo[event.buf].filetype)
        if #names > 0 then
            lint.try_lint(names)
        end
    end,
})
