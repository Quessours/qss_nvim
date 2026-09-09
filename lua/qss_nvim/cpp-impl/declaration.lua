local macros = require('qss_nvim.cpp.macros')
local structure = require('qss_nvim.cpp.structure')
local text = require('qss_nvim.cpp.text')

local LANG = 'cpp'

local M = {}

--- Nodes that hold a declaration a definition can be written for.
local DECLARATIONS = { field_declaration = true, declaration = true }

--- Nodes a declaration search never enters. A declaration inside a body is a
--- local variable.
local BODIES = { function_definition = true, compound_statement = true }

--- Words that belong to the declaration alone.
local DROPPED = {
    ['virtual'] = true,
    ['explicit'] = true,
    ['friend'] = true,
    ['override'] = true,
    ['final'] = true,
}

--- Words that keep a function in the header, whatever the cursor asks for.
local HEADER_ONLY = { ['inline'] = true, ['constexpr'] = true, ['consteval'] = true }

---@param bufnr integer
---@param from_row integer
---@param from_col integer
---@param to_row integer
---@param to_col integer
---@return string
local function span(bufnr, from_row, from_col, to_row, to_col)
    local lines = vim.api.nvim_buf_get_text(bufnr, from_row, from_col, to_row, to_col, {})
    local in_block = false
    for index, line in ipairs(lines) do
        lines[index], in_block = text.code_of(line, in_block)
    end
    local joined = table.concat(lines, ' '):gsub('%s+', ' ')
    return vim.trim(joined)
end

---@param node TSNode
---@param bufnr integer
---@return string
local function node_span(node, bufnr)
    local from_row, from_col = node:start()
    local to_row, to_col = node:end_()
    return span(bufnr, from_row, from_col, to_row, to_col)
end

--- The return type and the qualifiers, without the words a definition must
--- not repeat. A Qt macro goes with them, and so does an attribute.
---@param written string
---@param in_class boolean
---@return string kept, string? header_only
local function specifiers(written, in_class)
    local kept = {}

    for _, token in ipairs(text.tokens_of(written)) do
        local word = token:match('^([%a_][%w_]*)') or ''
        if HEADER_ONLY[word] then
            return '', word
        end

        local is_qt_macro = token:match('^Q_[%u%d_]+') ~= nil
        local is_attribute = token:match('^%[%[') ~= nil
        local is_static_member = in_class and word == 'static'
        local drop = DROPPED[word] or is_qt_macro or is_attribute or is_static_member
        if not drop then
            kept[#kept + 1] = token
        end
    end

    return table.concat(kept, ' '), nil
end

--- The parameter as the definition writes it. A default argument belongs to
--- the declaration only, so the text is cut at the '=' that introduces it.
---@param node TSNode
---@param bufnr integer
---@return string
local function parameter_of(node, bufnr)
    local default = node:field('default_value')[1]
    if not default then
        return node_span(node, bufnr)
    end

    local from_row, from_col = node:start()
    local cut_row, cut_col = default:start()
    for child in node:iter_children() do
        if not child:named() and vim.treesitter.get_node_text(child, bufnr) == '=' then
            cut_row, cut_col = child:start()
            break
        end
    end
    return span(bufnr, from_row, from_col, cut_row, cut_col)
end

---@param list TSNode a parameter_list
---@param bufnr integer
---@return string
local function parameters_of(list, bufnr)
    local written = {}
    for child in list:iter_children() do
        if child:named() then
            written[#written + 1] = parameter_of(child, bufnr)
        elseif vim.treesitter.get_node_text(child, bufnr) == '...' then
            written[#written + 1] = '...'
        end
    end
    return table.concat(written, ', ')
end

---@class qss.cpp.impl.Parts
---@field name_from integer[] row and column the name starts at
---@field name_to integer[] row and column it ends at
---@field parameters TSNode
---@field tail TSNode the node the trailing qualifiers end with

--- The name, the parameters and the tail of a declarator, through the pointer
--- and reference declarators that wrap them.
---@param declarator TSNode
---@return qss.cpp.impl.Parts?
local function parts_of(declarator)
    ---@type TSNode?
    local node = declarator
    while node and structure.WRAPPERS[node:type()] do
        node = structure.inner_declarator(node)
    end
    if not node then
        return nil
    end

    if node:type() == 'operator_cast' then
        local inner = node:field('declarator')[1]
        local parameters = inner and inner:field('parameters')[1]
        if not (inner and parameters) then
            return nil
        end
        return {
            name_from = { node:start() },
            name_to = { inner:start() },
            parameters = parameters,
            tail = inner,
        }
    end

    if node:type() ~= 'function_declarator' then
        return nil
    end

    local parameters = node:field('parameters')[1]
    ---@type TSNode?
    local named = structure.inner_declarator(node)
    while named and structure.WRAPPERS[named:type()] do
        named = structure.inner_declarator(named)
    end
    if not (parameters and named) then
        return nil
    end

    return {
        name_from = { named:start() },
        name_to = { named:end_() },
        parameters = parameters,
        tail = node,
    }
end

--- The namespaces around a node, and what those parents say about it. A
--- friend function is not a member, so the class it is declared in gives it no
--- qualification: `friend` puts the declaration in a friend_declaration node
--- of its own, one level above.
---@param node TSNode
---@param bufnr integer
---@return string[] namespaces, boolean templated, boolean anonymous, boolean friended
local function namespaces_of(node, bufnr)
    local namespaces, templated, anonymous, friended = {}, false, false, false

    local parent = node:parent()
    while parent do
        local kind = parent:type()
        if kind == 'template_declaration' then
            templated = true
        elseif kind == 'friend_declaration' then
            friended = true
        elseif kind == 'namespace_definition' then
            local name = parent:field('name')[1]
            if name then
                table.insert(namespaces, 1, vim.treesitter.get_node_text(name, bufnr))
            else
                anonymous = true
            end
        end
        parent = parent:parent()
    end

    return namespaces, templated, anonymous, friended
end

--- The section a row sits in.
---@param class qss.cpp.ClassInfo
---@param row integer
---@return qss.cpp.Section?
local function section_at(class, row)
    local found
    for _, section in ipairs(class.sections) do
        if section.label_row and section.label_row <= row then
            found = section
        end
    end
    return found
end

---@class qss.cpp.Declaration
---@field first integer 0-based row the declaration starts on
---@field last integer 0-based row it ends on
---@field name string the name as written, '~Foo' and 'operator=' included
---@field scope string the class or namespace path the definition qualifies with
---@field owner string the last segment of the scope, for a title
---@field prefix string the return type as the header wrote it
---@field parameters string the parameter list, without default arguments
---@field suffix string const, noexcept, a ref-qualifier, a trailing return type
---@field in_class boolean true when the scope names a class rather than a namespace
---@field types table<string, true> the types the class declares, for the return type

--- The declaration a node holds, or the reason it has no definition to write.
---@param bufnr integer
---@param node TSNode
---@return qss.cpp.Declaration? declaration, string? reason
local function read(bufnr, node)
    local declarator = node:field('declarator')[1]
    local parts = declarator and parts_of(declarator)
    if not parts then
        return nil, 'only a function declaration can be implemented'
    end

    if node:field('default_value')[1] then
        return nil, 'a pure virtual function has no definition to write'
    end

    local namespaces, templated, anonymous, friended = namespaces_of(node, bufnr)
    if templated then
        return nil, 'a template is defined in the header'
    end
    if anonymous then
        return nil, 'an anonymous namespace cannot be reopened from another file'
    end

    local first_row, first_col = node:start()
    local last_row = node:end_()
    local prefix = span(bufnr, first_row, first_col, parts.name_from[1], parts.name_from[2])

    local class = nil
    if not friended then
        class = structure.class_at(bufnr, first_row)
    end

    if class then
        local section = section_at(class, first_row)
        if section and section.kind == 'signals' then
            return nil, 'moc writes every signal body'
        end
        if class.templated then
            return nil, 'a template is defined in the header'
        end
        if class.anonymous_namespace then
            return nil, 'an anonymous namespace cannot be reopened from another file'
        end
    end

    local kept, header_only = specifiers(prefix, class ~= nil)
    if header_only then
        return nil, ('%s keeps the definition in the header'):format(header_only)
    end

    local scope = class and class.qualified or table.concat(namespaces, '::')
    local segments = vim.split(scope, '::', { plain = true })

    local name = span(bufnr, parts.name_from[1], parts.name_from[2], parts.name_to[1], parts.name_to[2])

    if kept == '' then
        local is_constructor = class ~= nil and name == class.name
        local is_destructor = name:match('^~') ~= nil
        local is_conversion = name:match('^operator%A') ~= nil
        local names_a_function = is_constructor or is_destructor or is_conversion
        if not names_a_function then
            return nil, ('%s declares no function'):format(name)
        end
    end

    local parameters_row, parameters_col = parts.parameters:end_()
    local tail_row, tail_col = parts.tail:end_()
    local suffix = specifiers(span(bufnr, parameters_row, parameters_col, tail_row, tail_col), false)

    return {
        first = first_row,
        last = last_row,
        name = name,
        scope = scope,
        owner = segments[#segments] or '',
        prefix = kept,
        parameters = parameters_of(parts.parameters, bufnr),
        suffix = suffix,
        in_class = class ~= nil,
        types = class and class.types or {},
    }, nil
end

--- Every declaration node overlapping a row range, outermost first.
---@param written string the buffer text, macro rows blanked
---@param from integer
---@param to integer
---@return TSNode[]
local function nodes_in(written, from, to)
    local ok, parser = pcall(vim.treesitter.get_string_parser, written, LANG)
    if not ok or not parser then
        return {}
    end

    local tree = parser:parse()[1]
    if not tree then
        return {}
    end

    ---@type TSNode[]
    local found = {}

    ---@param node TSNode
    local function search(node)
        for child in node:iter_children() do
            local overlaps = child:start() <= to and child:end_() >= from
            if overlaps then
                if DECLARATIONS[child:type()] then
                    found[#found + 1] = child
                elseif not BODIES[child:type()] then
                    search(child)
                end
            end
        end
    end
    search(tree:root())

    return found
end

--- The buffer text a parse reads.
---@param bufnr integer
---@return string
local function readable(bufnr)
    return macros.blanked(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

--- The declaration on a row.
---@param bufnr integer
---@param row integer 0-based
---@return qss.cpp.Declaration? declaration, string? reason
function M.at(bufnr, row)
    local nodes = nodes_in(readable(bufnr), row, row)
    if #nodes == 0 then
        return nil, 'no declaration on this line'
    end
    return read(bufnr, nodes[#nodes])
end

--- Every declaration in a row range that has a definition to write.
---@param bufnr integer
---@param from integer 0-based
---@param to integer 0-based
---@return qss.cpp.Declaration[]
function M.in_range(bufnr, from, to)
    local found = {}
    for _, node in ipairs(nodes_in(readable(bufnr), from, to)) do
        local declaration = read(bufnr, node)
        if declaration then
            found[#found + 1] = declaration
        end
    end
    return found
end

return M
