return {}
--local lsp = require('lsp-zero').preset({})

lsp.on_attach(function(client, bufnr)
    lsp.default_keymaps({ buffer = bufnr })
end)

-- Why did I disabled clangd setup ???
--lsp.skip_server_setup({ 'rust_analyzer', 'clangd' })
lsp.skip_server_setup({ 'rust_analyzer' })



-- (Optional) Configure lua language server for neovim
require('lspconfig').lua_ls.setup(lsp.nvim_lua_ls())
require('lspconfig').sqlls.setup { root_dir = require('lspconfig').util.find_git_ancestor }

-- Why doesn't it work ??
require('lspconfig').qmlls.setup { cmd = { "qmlls" }, filetypes = { "qml", "qmljs" }, root_dir = require("lspconfig")
    .util
    .find_git_ancestor, single_file_support = true }
require 'lspconfig'.cmake.setup {}
require 'lspconfig'.pyright.setup {}
require 'lspconfig'.bashls.setup { single_file_support = true, shellcheckPath = "",
    filetypes = { "sh", "bash" } }
lsp.setup()


local function border(hl_name)
    return {
        { "╭", hl_name },
        { "─", hl_name },
        { "╮", hl_name },
        { "│", hl_name },
        { "╯", hl_name },
        { "─", hl_name },
        { "╰", hl_name },
        { "│", hl_name },
    }
end

local cmp = require('cmp')
local options = {
    mapping = {
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<C-d>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),
    },
    sources = {
        { name = 'path' },
        { name = 'nvim_lsp' },
        { name = 'buffer',  keyword_length = 3 },
        { name = 'luasnip', keyword_length = 2 },
    },
    preselect = 'item',
    completion = {
        completeopt = 'menu,menuone,noinsert'
    },
    window = {
        documentation = {
            border = border "CmpDocBorder",
            winhighlight = "Normal:CmpDoc",
        },
    }
}
local cmp_autopairs = require('nvim-autopairs.completion.cmp')

cmp.event:on(
    'confirm_done',
    cmp_autopairs.on_confirm_done()
)

cmp.setup(options)
