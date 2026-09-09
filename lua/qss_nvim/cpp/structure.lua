local macros = require('qss_nvim.cpp.macros')
local text = require('qss_nvim.cpp.text')

local LANG = 'cpp'

local M = {}

--- Every node type that can stand where a declarator is expected.
local DECLARATORS = {
    function_declarator = true,
    field_identifier = true,
    identifier = true,
    qualified_identifier = true,
    destructor_name = true,
    operator_name = true,
    pointer_declarator = true,
    reference_declarator = true,
    array_declarator = true,
    init_declarator = true,
    parenthesized_declarator = true,
}

--- Declarators that wrap the name.
local WRAPPERS = {
    pointer_declarator = true,
    reference_declarator = true,
    array_declarator = true,
    init_declarator = true,
    parenthesized_declarator = true,
}

--- Nodes that declare a type of their own.
local SPECIFIERS = {
    enum_specifier = true,
    class_specifier = true,
    struct_specifier = true,
    union_specifier = true,
}

--- Children of a class body that never declare a member.
local NOT_MEMBERS = {
    access_specifier = true,
    comment = true,
    ERROR = true,
}

--- The access labels a section can carry.
local ACCESS = { public = true, protected = true, private = true }

---@param node TSNode
---@param bufnr integer
---@return string
local function text_of(node, bufnr)
    return vim.treesitter.get_node_text(node, bufnr)
end

---@param node TSNode
---@param name string
---@return TSNode?
local function field(node, name)
    return node:field(name)[1]
end

---@param node TSNode
---@param wanted string
---@return TSNode?
local function child_of_type(node, wanted)
    for child in node:iter_children() do
        if child:type() == wanted then
            return child
        end
    end
    return nil
end

--- The declarator inside another one. `pointer_declarator` exposes its child
--- as a `declarator` field, but `reference_declarator` does not, so the field
--- alone loses every reference-returning member.
---@param node TSNode
---@return TSNode?
local function inner_declarator(node)
    local named = field(node, 'declarator')
    if named then
        return named
    end
    for child in node:iter_children() do
        if child:named() and DECLARATORS[child:type()] then
            return child
        end
    end
    return nil
end

--- The identifier a declarator finally names, through pointers, references,
--- arrays and initializers.
---@param declarator TSNode
---@param bufnr integer
---@return string? name
local function declared_name(declarator, bufnr)
    ---@type TSNode?
    local node = declarator

    while node and WRAPPERS[node:type()] do
        node = inner_declarator(node)
    end
    if not node then
        return nil
    end

    if node:type() == 'function_declarator' then
        node = inner_declarator(node)
        while node and WRAPPERS[node:type()] do
            node = inner_declarator(node)
        end
    end
    if not node then
        return nil
    end

    local kind = node:type()
    local names_something = kind == 'field_identifier' or kind == 'identifier'
        or kind == 'destructor_name' or kind == 'operator_name'
        or kind == 'qualified_identifier'
    if not names_something then
        return nil
    end
    return text_of(node, bufnr)
end

---@class qss.cpp.Section
---@field kind string 'public'|'protected'|'private'|'signals', with ' slots' appended
---@field label_row integer? nil for the section before any label
---@field last integer the last row that belongs to the section
---@field indent string? the indentation its members use

--- The label a row opens a section with, or nil.
---
--- This is a line scan rather than a node walk, because tree-sitter gives Qt's
--- section labels nothing to stand on. `signals:` becomes an ERROR node, and
--- `Q_SIGNALS:` is swallowed whole by the declaration above it.
---@param line string
---@return string?
local function label_of(line)
    local access, slots = line:match('^%s*([%a_]+)%s+(slots)%s*:')
    if access and ACCESS[access] then
        return ('%s %s'):format(access, slots)
    end

    local plain = line:match('^%s*([%a_]+)%s*:')
    if not plain then
        return nil
    end
    if ACCESS[plain] then
        return plain
    end
    if plain == 'signals' or plain == 'Q_SIGNALS' then
        return 'signals'
    end
    return nil
end

--- The sections of a class body, in the order they appear.
---
--- A row belongs to the body itself only when the brace depth returns to one
--- by the end of it. That is what keeps the closing brace of an inline
--- function definition, rather than its opening brace, as a section's last
--- row.
---@param body TSNode
---@param code string[] every line of the buffer, comments blanked, 1-based
---@return qss.cpp.Section[]
local function sections_of(body, code)
    local first, last_row = body:start(), body:end_()

    ---@type qss.cpp.Section[]
    local sections = { { kind = 'implicit', label_row = nil, last = first } }
    local current = sections[1]
    local depth = 0

    for row = first, last_row do
        local line = code[row + 1] or ''
        depth = depth + select(2, line:gsub('{', '')) - select(2, line:gsub('}', ''))

        if depth == 1 then
            local label = label_of(line)
            if label then
                current = { kind = label, label_row = row, last = row }
                sections[#sections + 1] = current
            elseif vim.trim(line) ~= '' then
                current.last = row
                if not current.indent and row > first then
                    current.indent = line:match('^%s*')
                end
            end
        end
    end

    return sections
end

---@param node TSNode
---@param row integer
---@return boolean
local function covers(node, row)
    return node:start() <= row and row <= node:end_()
end

--- Every name the class declares: functions, fields, nested types. The types
--- come back on their own as well, because a definition in the source file
--- names one of them from outside the class.
---@param body TSNode
---@param bufnr integer
---@return table<string, true> declared, table<string, true> types
local function declared_in(body, bufnr)
    local declared, types = {}, {}

    ---@param node TSNode
    local function record(node)
        local name = field(node, 'name') or field(node, 'declarator')
        if not name then
            return
        end
        local written = text_of(name, bufnr)
        declared[written] = true
        types[written] = true
    end

    ---@param child TSNode
    ---@return TSNode? specifier
    local function type_specifier(child)
        if SPECIFIERS[child:type()] then
            return child
        end
        local inner = field(child, 'type')
        local declares_a_type = inner ~= nil and SPECIFIERS[inner:type()]
        return declares_a_type and inner or nil
    end

    ---@param node TSNode
    local function collect(node)
        for child in node:iter_children() do
            local kind = child:type()

            if kind == 'template_declaration' then
                collect(child)
            elseif kind == 'alias_declaration' or kind == 'type_definition' then
                record(child)
            elseif not NOT_MEMBERS[kind] then
                local specifier = type_specifier(child)
                if specifier then
                    record(specifier)
                end
                for _, declarator in ipairs(child:field('declarator')) do
                    local name = declared_name(declarator, bufnr)
                    if name then
                        declared[name] = true
                    end
                end
            end
        end
    end

    collect(body)
    return declared, types
end

---@class qss.cpp.ClassInfo
---@field name string
---@field node TSNode
---@field body TSNode
---@field namespaces string[] outermost first
---@field qualified string the name a definition in the .cpp uses
---@field templated boolean
---@field anonymous_namespace boolean
---@field sections qss.cpp.Section[]
---@field declared table<string, true>
---@field types table<string, true> the nested types, out of `declared`
---@field has_q_object boolean
---@field one_line boolean

--- The innermost class or struct whose body covers a row.
---@param bufnr integer
---@param row integer 0-based
---@return qss.cpp.ClassInfo? class, string? reason
function M.class_at(bufnr, row)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local code = text.code_lines(lines)

    local ok, parser = pcall(vim.treesitter.get_string_parser, macros.blanked(lines), LANG)
    if not ok or not parser then
        return nil, 'the cpp treesitter parser is not available'
    end

    local tree = parser:parse()[1]
    if not tree then
        return nil, 'the buffer could not be parsed'
    end

    ---@type TSNode?
    local found
    ---@param node TSNode
    local function search(node)
        for child in node:iter_children() do
            if covers(child, row) then
                local kind = child:type()
                if kind == 'class_specifier' or kind == 'struct_specifier' then
                    if child:field('body')[1] then
                        found = child
                    end
                end
                search(child)
            end
        end
    end
    search(tree:root())

    if not found then
        return nil, 'the cursor is not inside a class'
    end

    local body = field(found, 'body')
    local name_node = field(found, 'name')
    if not (body and name_node) then
        return nil, 'the class has no name or no body'
    end

    local namespaces, anonymous = {}, false
    local parent = found:parent()
    local templated = false
    while parent do
        local kind = parent:type()
        if kind == 'template_declaration' then
            templated = true
        elseif kind == 'namespace_definition' then
            local namespace = field(parent, 'name')
            if namespace then
                table.insert(namespaces, 1, text_of(namespace, bufnr))
            else
                anonymous = true
            end
        end
        parent = parent:parent()
    end

    local name = text_of(name_node, bufnr)
    local qualified = name
    if #namespaces > 0 then
        qualified = ('%s::%s'):format(table.concat(namespaces, '::'), name)
    end

    local has_q_object = false
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, found:start(), body:end_() + 1, false)) do
        if line:match('^%s*Q_OBJECT%s*$') or line:match('^%s*Q_GADGET%s*$') then
            has_q_object = true
            break
        end
    end

    local declared, types = declared_in(body, bufnr)

    return {
        name = name,
        node = found,
        body = body,
        namespaces = namespaces,
        qualified = qualified,
        templated = templated,
        anonymous_namespace = anonymous,
        sections = sections_of(body, code),
        declared = declared,
        types = types,
        has_q_object = has_q_object,
        one_line = body:start() == body:end_(),
    }, nil
end

--- Flatten a qualified_identifier chain into 'app::ui::Foo::setName'.
---
--- A conversion operator holds its parameter list inside its own name node, so
--- that tail is taken back off: 'operator QString() const' is the name
--- 'operator QString'.
---@param node TSNode
---@param text string
---@return string
local function flatten(node, text)
    if node:type() == 'operator_cast' then
        local written = vim.treesitter.get_node_text(node, text)
        local inner = node:field('declarator')[1]
        if inner then
            local tail = vim.treesitter.get_node_text(inner, text)
            if written:sub(-#tail) == tail then
                written = written:sub(1, #written - #tail)
            end
        end
        return vim.trim(written)
    end

    if node:type() ~= 'qualified_identifier' then
        return vim.treesitter.get_node_text(node, text)
    end
    local scope = node:field('scope')[1]
    local name = node:field('name')[1]
    local head = scope and vim.treesitter.get_node_text(scope, text) or ''
    local tail = name and flatten(name, text) or ''
    if head == '' then
        return tail
    end
    return ('%s::%s'):format(head, tail)
end

---@class qss.cpp.Defined
---@field key string the last two qualified segments, 'Class::member'
---@field qualified string the name as the definition writes it
---@field first integer 0-based row the definition starts on
---@field last integer 0-based row its closing brace sits on
---@field namespaces string[] the namespace blocks open around it, outermost first

--- The last two segments of a qualified name. A definition written inside
--- reopened namespace blocks and one written fully qualified then match the
--- same key.
---@param qualified string
---@return string
local function key_of(qualified)
    local segments = vim.split(qualified, '::', { plain = true })
    if #segments >= 2 then
        return ('%s::%s'):format(segments[#segments - 1], segments[#segments])
    end
    return qualified
end

--- Every function a file defines, in the order they appear.
---@param text string the whole file
---@return qss.cpp.Defined[]
function M.definitions(text)
    ---@type qss.cpp.Defined[]
    local found = {}

    local ok, parser = pcall(vim.treesitter.get_string_parser, text, LANG)
    if not ok or not parser then
        return found
    end

    local tree = parser:parse()[1]
    if not tree then
        return found
    end

    ---@param node TSNode
    ---@param namespaces string[]
    local function search(node, namespaces)
        for child in node:iter_children() do
            local kind = child:type()
            local inner = namespaces

            if kind == 'namespace_definition' then
                inner = vim.list_extend({}, namespaces)
                local name = child:field('name')[1]
                if name then
                    local written = vim.treesitter.get_node_text(name, text)
                    vim.list_extend(inner, vim.split(written, '::', { plain = true }))
                end
            elseif kind == 'function_definition' then
                ---@type TSNode?
                local declarator = child:field('declarator')[1]
                while declarator and WRAPPERS[declarator:type()] do
                    declarator = inner_declarator(declarator)
                end

                ---@type TSNode?
                local named
                if declarator then
                    local shape = declarator:type()
                    if shape == 'function_declarator' then
                        named = inner_declarator(declarator)
                    elseif shape == 'qualified_identifier' or shape == 'operator_cast' then
                        named = declarator
                    end
                end

                if named then
                    local qualified = flatten(named, text)
                    found[#found + 1] = {
                        key = key_of(qualified),
                        qualified = qualified,
                        first = child:start(),
                        last = child:end_(),
                        namespaces = namespaces,
                    }
                end
            end

            search(child, inner)
        end
    end
    search(tree:root(), {})

    return found
end

--- The member functions a source file already defines, keyed the same way.
---@param path string
---@return table<string, true>
function M.defined_names(path)
    local defined = {}
    if vim.fn.filereadable(path) ~= 1 then
        return defined
    end

    for _, definition in ipairs(M.definitions(table.concat(vim.fn.readfile(path), '\n'))) do
        defined[definition.key] = true
    end
    return defined
end

--- The declarator walk, for a reader that starts from a declaration of its own
--- rather than from a class body.
M.WRAPPERS = WRAPPERS
M.inner_declarator = inner_declarator
M.declared_name = declared_name

return M
