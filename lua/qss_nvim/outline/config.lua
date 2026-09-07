-- Ported from the old symbols-outline.nvim opts with the upstream
-- scripts/convert-symbols-outline-opts.lua script, then corrected by hand:
-- see the notes on symbol_folding, providers and symbols.filter below.
return {
    guides = {
        enabled = true,
    },
    outline_items = {
        highlight_hovered_item = true,
        show_symbol_details = true,
    },
    outline_window = {
        position = 'right',
        relative_width = true,
        width = 25,
        auto_close = false,
        show_numbers = false,
        show_relative_numbers = false,
        wrap = false,
    },
    preview_window = {
        auto_preview = false,
        -- Was preview_bg_highlight = 'Pmenu'.
        winhl = 'Normal:Pmenu',
    },
    providers = {
        -- Spell out the whole list. vim.tbl_deep_extend('force', ...) replaces
        -- a list rather than merging it, so priority = { 'qml' } on its own
        -- would drop lsp, coc, markdown, norg and man for every other language.
        priority = { 'qml', 'lsp', 'coc', 'markdown', 'norg', 'man' },
        -- Read by lua/outline/providers/qml.lua. Flip any of these to change
        -- what the QML outline shows. Hiding a container hoists its children
        -- into the parent, so turning off binding_groups keeps the State
        -- objects inside states: [ ... ] and only drops the states row.
        qml = {
            filetypes = { 'qml', 'qmljs' },
            show = {
                objects         = true,  -- Rectangle { }
                components      = true,  -- component Badge: Rectangle { }
                enums           = true,  -- enum Mode { Idle, Busy }
                enum_members    = true,  -- Idle, Busy
                properties      = true,  -- property int level
                signals         = true,  -- signal changed(string key)
                functions       = true,  -- function helper(a, b) { }
                signal_handlers = true,  -- onClicked: { }
                binding_groups  = true,  -- states: [ State { } ], delegate: Item { }
                bindings        = false, -- text: "go", spacing: 8
                imports         = false, -- import QtQuick 2.15
                pragmas         = false, -- pragma ComponentBehavior: Bound
            },
        },
    },
    symbol_folding = {
        -- outline.nvim folds past depth 1 by default. The old config left
        -- autofold_depth unset, which meant no folding, and false is how
        -- outline.nvim spells that.
        autofold_depth = false,
        -- Canonical spelling of the old auto_unfold_hover = false.
        auto_unfold = { hovered = false },
        markers = { '', '' },
    },
    keymaps = {
        close = "q",
        goto_location = "<Cr>",
        -- Renamed from focus_location.
        peek_location = "f",
        hover_symbol = "<C-space>",
        toggle_preview = "p",
        rename_symbol = "r",
        code_actions = "a",
        fold = "h",
        unfold = "l",
        fold_all = "W",
        unfold_all = "E",
        fold_reset = "R",
    },
    symbols = {
        -- Treesitter capture names, because the old @text.uri, @namespace,
        -- @method, @field and @parameter groups no longer resolve on 0.11.
        icons = {
            File = { icon = "", hl = "@string.special.url" },
            Module = { icon = "", hl = "@module" },
            Namespace = { icon = "", hl = "@module" },
            Package = { icon = "", hl = "@module" },
            Class = { icon = "𝓒", hl = "@type" },
            Method = { icon = "ƒ", hl = "@function.method" },
            Property = { icon = "", hl = "@function.method" },
            Field = { icon = "", hl = "@variable.member" },
            Constructor = { icon = "", hl = "@constructor" },
            Enum = { icon = "ℰ", hl = "@type" },
            Interface = { icon = "ﰮ", hl = "@type" },
            Function = { icon = "", hl = "@function" },
            Variable = { icon = "", hl = "@constant" },
            Constant = { icon = "", hl = "@constant" },
            String = { icon = "𝓐", hl = "@string" },
            Number = { icon = "#", hl = "@number" },
            Boolean = { icon = "⊨", hl = "@boolean" },
            Array = { icon = "", hl = "@constant" },
            Object = { icon = "⦿", hl = "@type" },
            Key = { icon = "🔐", hl = "@type" },
            Null = { icon = "NULL", hl = "@type" },
            EnumMember = { icon = "", hl = "@variable.member" },
            Struct = { icon = "𝓢", hl = "@type" },
            Event = { icon = "🗲", hl = "@type" },
            Operator = { icon = "+", hl = "@operator" },
            TypeParameter = { icon = "𝙏", hl = "@variable.parameter" },
            Component = { icon = "", hl = "@function" },
            Fragment = { icon = "", hl = "@constant" },
            -- Kinds outline.nvim adds on top of the symbols-outline set.
            TypeAlias = { icon = " ", hl = "@type" },
            Parameter = { icon = " ", hl = "@variable.parameter" },
            StaticMethod = { icon = " ", hl = "@function.method" },
            Macro = { icon = " ", hl = "@function.macro" },
        },
    },
}
