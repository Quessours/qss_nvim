--- outline.nvim provider for QML, backed by the qmljs treesitter grammar.
---
--- Qt's qmlls does not implement textDocument/documentSymbol (checked against
--- 6.8.2), so outline.nvim's LSP provider cannot claim a QML buffer. This reads
--- the syntax tree instead, which carries more structure than the LSP symbol
--- kinds express: properties keep their type and modifiers, signals keep their
--- parameters, and inline components stay distinct from plain objects.
---
--- Registered by adding 'qml' to providers.priority in
--- qss_nvim/outline/config.lua, where providers.qml.show also lives.

local lsp = require('outline.providers.nvim-lsp')

local M = {
    name = 'qml',
}

local LANG = 'qmljs'

local default_filetypes = { 'qml', 'qmljs' }

local default_show = {
    objects         = true,
    components      = true,
    enums           = true,
    enum_members    = true,
    properties      = true,
    signals         = true,
    functions       = true,
    signal_handlers = true,
    binding_groups  = true,
    bindings        = false,
    imports         = false,
    pragmas         = false,
}

-- Reported by get_status, for :OutlineStatus.
local last_count = 0

local function count_deep(symbols)
    local n = 0
    for _, sym in ipairs(symbols) do
        n = n + 1 + count_deep(sym.children or {})
    end
    return n
end

local function get_show()
    local provider_config = require('outline.config').o.providers[M.name] or {}
    return vim.tbl_extend('force', default_show, provider_config.show or {})
end

local function text_of(node, bufnr)
    if not node then
        return nil
    end
    return vim.treesitter.get_node_text(node, bufnr)
end

--- Collapse a node's text to one line, for the detail column.
local function summarize(node, bufnr, limit)
    local raw = text_of(node, bufnr)
    if not raw then
        return nil
    end
    local flat = vim.trim((raw:gsub('%s+', ' ')))
    if flat == '' then
        return nil
    end
    if vim.fn.strchars(flat) > limit then
        return vim.fn.strcharpart(flat, 0, limit - 1) .. '…'
    end
    return flat
end

local function field(node, name)
    return node:field(name)[1]
end

local function child_of_type(node, wanted)
    for child in node:iter_children() do
        if child:type() == wanted then
            return child
        end
    end
    return nil
end

--- Build one symbol table in the shape outline.nvim expects. Lines are
--- 0-based, matching treesitter and the LSP protocol. range spans the whole
--- construct and drives folding; selection_node is what <Cr> jumps to.
---@param name string
---@param kind string
---@param selection_node TSNode
---@param range_node TSNode
---@param detail string?
local function symbol(name, kind, selection_node, range_node, detail)
    local sel_row, sel_col, sel_end_row, sel_end_col = selection_node:range()
    local row, col, end_row, end_col = range_node:range()
    return {
        name = name,
        kind = kind,
        detail = detail,
        selectionRange = {
            start = { line = sel_row, character = sel_col },
            ['end'] = { line = sel_end_row, character = sel_end_col },
        },
        range = {
            start = { line = row, character = col },
            ['end'] = { line = end_row, character = end_col },
        },
        children = {},
    }
end

--- A hidden container hoists its children into its parent. A hidden leaf just
--- disappears. This is why the show table lives here and not in
--- outline.nvim's symbols.filter, which drops the whole subtree instead
--- (see the FIXME in outline/parser.lua).
local function emit(out, visible, sym, children)
    if not visible then
        vim.list_extend(out, children or {})
        return
    end
    sym.children = children or {}
    table.insert(out, sym)
end

local collect
local handle_object

--- Objects own their `id` binding: it becomes the detail rather than a row.
local function object_id(object_node, bufnr)
    local initializer = field(object_node, 'initializer')
    if not initializer then
        return nil
    end
    for child in initializer:iter_children() do
        if child:type() == 'ui_binding' then
            local name = field(child, 'name')
            if name and text_of(name, bufnr) == 'id' then
                return summarize(field(child, 'value'), bufnr, 40)
            end
        end
    end
    return nil
end

--- states: [ State { } ] and property list<T> p: [ T { } ] both nest objects
--- in their value. Returns their symbols, or nil when the value holds none.
local function objects_in_value(value, bufnr, show)
    if not value then
        return nil
    end
    local kind = value:type()
    local children = {}
    if kind == 'ui_object_definition' then
        handle_object(value, bufnr, show, children)
    elseif kind == 'ui_object_array' then
        for child in value:iter_children() do
            if child:type() == 'ui_object_definition' then
                handle_object(child, bufnr, show, children)
            end
        end
    else
        return nil
    end
    return children
end

function handle_object(node, bufnr, show, out)
    local type_name = field(node, 'type_name')
    local initializer = field(node, 'initializer')
    local children = initializer and collect(initializer, bufnr, show) or {}
    if not type_name then
        vim.list_extend(out, children)
        return
    end
    emit(out, show.objects, symbol(
        text_of(type_name, bufnr),
        'Class',
        type_name,
        node,
        object_id(node, bufnr)
    ), children)
end

local function handle_inline_component(node, bufnr, show, out)
    local name = field(node, 'name')
    local inner = field(node, 'component')
    local children = {}
    if inner then
        handle_object(inner, bufnr, show, children)
    end
    if not name then
        vim.list_extend(out, children)
        return
    end
    local inner_type = inner and text_of(field(inner, 'type_name'), bufnr) or nil
    emit(out, show.components,
        symbol(text_of(name, bufnr), 'Component', name, node, inner_type), children)
end

local function handle_enum(node, bufnr, show, out)
    local name = field(node, 'name')
    local body = field(node, 'body')
    local members = {}
    if body and show.enum_members then
        for _, member in ipairs(body:field('name')) do
            table.insert(members,
                symbol(text_of(member, bufnr), 'EnumMember', member, member, nil))
        end
    end
    if not name then
        vim.list_extend(out, members)
        return
    end
    emit(out, show.enums, symbol(text_of(name, bufnr), 'Enum', name, node, nil), members)
end

local function handle_property(node, bufnr, show, out)
    local name = field(node, 'name')
    if not name then
        return
    end
    local type_text = text_of(field(node, 'type'), bufnr)
    local modifier = text_of(child_of_type(node, 'ui_property_modifier'), bufnr)
    local detail = type_text
    if type_text and modifier then
        detail = type_text .. ', ' .. modifier
    elseif modifier then
        detail = modifier
    end
    local children = objects_in_value(field(node, 'value'), bufnr, show)
    emit(out, show.properties,
        symbol(text_of(name, bufnr), 'Property', name, node, detail), children or {})
end

local function handle_signal(node, bufnr, show, out)
    local name = field(node, 'name')
    if not name then
        return
    end
    local types = {}
    local parameters = field(node, 'parameters')
    if parameters then
        for child in parameters:iter_children() do
            if child:type() == 'ui_signal_parameter' then
                table.insert(types, text_of(field(child, 'type'), bufnr) or '?')
            end
        end
    end
    emit(out, show.signals, symbol(
        text_of(name, bufnr),
        'Event',
        name,
        node,
        '(' .. table.concat(types, ', ') .. ')'
    ), {})
end

local function handle_function(node, bufnr, show, out)
    local name = field(node, 'name')
    if not name then
        return
    end
    emit(out, show.functions, symbol(
        text_of(name, bufnr),
        'Function',
        name,
        node,
        summarize(field(node, 'parameters'), bufnr, 40)
    ), {})
end

--- Bindings are three different things wearing one node type:
--- a group holding objects (states:, delegate:), a signal handler (onClicked:),
--- or a plain value (spacing: 8).
local function handle_binding(node, bufnr, show, out)
    local name = field(node, 'name')
    if not name then
        return
    end
    local name_text = text_of(name, bufnr)
    -- Consumed by handle_object as the parent's detail.
    if name_text == 'id' then
        return
    end

    local value = field(node, 'value')

    local grouped = objects_in_value(value, bufnr, show)
    if grouped then
        emit(out, show.binding_groups,
            symbol(name_text, 'Array', name, node, nil), grouped)
        return
    end

    -- Component.onCompleted is a nested_identifier, so test the last segment.
    local leaf = name_text:match('[^.]+$') or name_text
    if leaf:match('^on%u') then
        emit(out, show.signal_handlers,
            symbol(name_text, 'Method', name, node, nil), {})
        return
    end

    emit(out, show.bindings,
        symbol(name_text, 'Field', name, node, summarize(value, bufnr, 40)), {})
end

local function handle_import(node, bufnr, show, out)
    local source = field(node, 'source')
    if not source then
        return
    end
    local detail = text_of(field(node, 'alias'), bufnr)
    if detail then
        detail = 'as ' .. detail
    else
        detail = text_of(field(node, 'version'), bufnr)
    end
    emit(out, show.imports,
        symbol(text_of(source, bufnr), 'Module', source, node, detail), {})
end

local function handle_pragma(node, bufnr, show, out)
    local name = field(node, 'name')
    if not name then
        return
    end
    emit(out, show.pragmas, symbol(
        text_of(name, bufnr),
        'Key',
        name,
        node,
        text_of(field(node, 'value'), bufnr)
    ), {})
end

local handlers = {
    ui_object_definition = handle_object,
    ui_inline_component = handle_inline_component,
    enum_declaration = handle_enum,
    ui_property = handle_property,
    ui_signal = handle_signal,
    function_declaration = handle_function,
    ui_binding = handle_binding,
    ui_import = handle_import,
    ui_pragma = handle_pragma,
}

--- Walk the named children of a container and return their symbols.
---@param container TSNode program or ui_object_initializer
---@param bufnr integer
---@param show table
---@return table[]
collect = function(container, bufnr, show)
    local out = {}
    for child in container:iter_children() do
        local handler = child:named() and handlers[child:type()] or nil
        if handler then
            handler(child, bufnr, show, out)
        end
    end
    return out
end

---@param bufnr integer
---@param config table? providers.qml from the outline.nvim config
---@return boolean supported, table? info
function M.supports_buffer(bufnr, config)
    local filetypes = (config and config.filetypes) or default_filetypes
    if not vim.tbl_contains(filetypes, vim.bo[bufnr].filetype) then
        return false
    end
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, LANG)
    if not ok or not parser then
        -- Fall through to the LSP provider rather than claiming the buffer.
        return false
    end
    return true, { bufnr = bufnr }
end

---@return string[]
function M.get_status()
    return {
        'parser: ' .. LANG,
        'symbols: ' .. last_count,
    }
end

---@param on_symbols fun(symbols?: table[], opts?: table)
---@param opts table
function M.request_symbols(on_symbols, opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, LANG)
    if not ok or not parser then
        on_symbols(nil, opts)
        return
    end
    local tree = parser:parse()[1]
    if not tree then
        on_symbols(nil, opts)
        return
    end
    local symbols = collect(tree:root(), bufnr, get_show())
    last_count = count_deep(symbols)
    on_symbols(symbols, opts)
end

-- qmlls does implement hover, rename and codeAction. These three take only a
-- sidebar and look up their own client by capability, so they work even though
-- the symbols came from treesitter. Keeps <C-space>, r and a alive in the
-- outline window.
M.show_hover = lsp.show_hover
M.rename_symbol = lsp.rename_symbol
M.code_actions = lsp.code_actions

return M
