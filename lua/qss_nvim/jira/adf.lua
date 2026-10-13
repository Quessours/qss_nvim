-- Jira Cloud stores a description as an Atlassian document: a tree of typed
-- nodes. Editing it as markdown means converting both ways.
--
-- Markdown has no way to write a panel, an inline card, a table or a media
-- node, so an earlier version of this file refused to open such a description
-- at all. That was the wrong trade: the API takes a document back whole, so a
-- block that markdown cannot express is replaced by a comment line, kept aside,
-- and put back untouched on save. Nothing is lost, and everything around it
-- stays editable.
local M = {}

local MARKS = {
    strong = '**',
    em = '*',
    code = '`',
    strike = '~~',
}

-- The Atlassian panel types, written the way the web editor names them in its
-- own slash menu. The canonical markdown spelling is the alert block that
-- GitHub and a dozen other renderers already understand, so a description stays
-- readable outside Neovim.
local PANELS = {
    info = true,
    note = true,
    tip = true,
    success = true,
    warning = true,
    error = true,
}

local PLACEHOLDER = '<!-- jira block %d, keep this line -->'
local PLACEHOLDER_PATTERN = '^<!%-%- jira block (%d+), keep this line %-%->$'

---@param lines string[]
local function trim_trailing_blanks(lines)
    while #lines > 0 and vim.trim(lines[#lines]) == '' do
        lines[#lines] = nil
    end
end

-- The order marks are written in, innermost first. Jira keeps them in any
-- order, so a fixed one is what lets the reader take them apart again:
-- `***x***` is always strong around em, and `~~**x**~~` strike around strong.
local MARK_ORDER = { 'code', 'em', 'strong', 'strike' }

-- The characters a backslash keeps literal, in the class a pattern takes.
local ESCAPABLE = '[%*`~%[\\]'

---@type fun(text: string): table[]
local inline_nodes

--- Whether plain text would read back as something else: a star taken for
--- emphasis, a bracket for a link. Only then is it escaped, so a log line or a
--- sum stays readable. A trailing backslash is escaped too, or the break after
--- it would read as an escaped character.
---@param text string
---@return boolean
local function needs_escape(text)
    if text == '' then
        return false
    end
    if text:match('\\$') then
        return true
    end
    local parsed = inline_nodes(text)
    return not (#parsed == 1 and parsed[1].text == text and parsed[1].marks == nil)
end

---@param node table
---@return string?
local function text_of(node)
    local held = {}
    local link

    for _, mark in ipairs(node.marks or {}) do
        if MARKS[mark.type] then
            held[mark.type] = true
        elseif mark.type == 'link' then
            link = mark.attrs and mark.attrs.href
        else
            return nil
        end
    end

    -- Jira shows a newline inside a text node as the line break it is, so each
    -- line is marked on its own and the newline becomes a break.
    local pieces = {}
    for _, piece in ipairs(vim.split(node.text or '', '\n', { plain = true })) do
        if not held.code and needs_escape(piece) then
            piece = piece:gsub(ESCAPABLE, '\\%0')
        end
        if piece ~= '' then
            for _, mark in ipairs(MARK_ORDER) do
                if held[mark] then
                    piece = MARKS[mark] .. piece .. MARKS[mark]
                end
            end
            if link then
                piece = ('[%s](%s)'):format(piece, link)
            end
        end
        pieces[#pieces + 1] = piece
    end
    return table.concat(pieces, '\n')
end

---@param nodes table[]
---@return string?
local function inline(nodes)
    local parts = {}
    for _, node in ipairs(nodes or {}) do
        if node.type == 'text' then
            local rendered = text_of(node)
            if not rendered then
                return nil
            end
            parts[#parts + 1] = rendered
        elseif node.type == 'hardBreak' then
            parts[#parts + 1] = '\n'
        else
            return nil
        end
    end
    return table.concat(parts)
end

---@param nodes table[]
---@param indent string
---@return string[]?
local function blocks(nodes, indent)
    local lines = {}

    ---@param text string
    local function push(text)
        for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
            lines[#lines + 1] = indent .. line
        end
    end

    for _, node in ipairs(nodes or {}) do
        if node.type == 'paragraph' and not node.content then
            -- An empty paragraph is a blank line in Jira and nothing in markdown.
            -- It is dropped rather than held by a comment line, because a
            -- comment line per blank line would bury the text it separates.
            lines[#lines + 1] = ''
        elseif node.type == 'paragraph' then
            local text = inline(node.content)
            if not text then
                return nil
            end
            -- A line break inside a paragraph ends on a backslash, which is how
            -- markdown itself writes a hard break. Without the mark, two breaks
            -- in a row look exactly like the blank line between two paragraphs,
            -- and one paragraph comes back as two.
            push((text:gsub('\n', '\\\n')))
            lines[#lines + 1] = ''
        elseif node.type == 'heading' then
            local text = inline(node.content)
            if not text then
                return nil
            end
            local level = node.attrs and node.attrs.level or 1
            push(('%s %s'):format(('#'):rep(level), (text:gsub('\n', '\\\n'))))
            lines[#lines + 1] = ''
        elseif node.type == 'codeBlock' then
            -- Code is taken as it is: nothing in it is markup, so nothing is
            -- escaped either.
            local parts = {}
            for _, child in ipairs(node.content or {}) do
                parts[#parts + 1] = child.text or ''
            end
            local text = table.concat(parts)
            local language = node.attrs and node.attrs.language or ''
            -- Markdown has no word for a wrapped code block, so the fence
            -- carries one after the language, where a renderer ignores it.
            local wrapped = node.attrs and node.attrs.wrap and ' wrap' or ''
            push(('```%s%s'):format(language, wrapped))
            push(text)
            push('```')
            lines[#lines + 1] = ''
        elseif node.type == 'rule' then
            push('---')
            lines[#lines + 1] = ''
        elseif node.type == 'blockquote' then
            local inner = blocks(node.content, '')
            if not inner then
                return nil
            end
            trim_trailing_blanks(inner)
            for _, line in ipairs(inner) do
                lines[#lines + 1] = indent .. '> ' .. line
            end
            lines[#lines + 1] = ''
        elseif node.type == 'panel' then
            local kind = node.attrs and node.attrs.panelType or 'info'
            local inner = blocks(node.content, '')
            if not (inner and PANELS[kind]) then
                return nil
            end
            trim_trailing_blanks(inner)
            push(('> [!%s]'):format(kind:upper()))
            for _, line in ipairs(inner) do
                push('> ' .. line)
            end
            lines[#lines + 1] = ''
        elseif node.type == 'taskList' then
            for _, item in ipairs(node.content or {}) do
                local text = inline(item.content)
                if not text then
                    return nil
                end
                local done = item.attrs and item.attrs.state == 'DONE'
                -- A break inside an item is the same backslash as in a
                -- paragraph, and the indent keeps the next line in the item.
                push(('- [%s] %s'):format(done and 'x' or ' ', (text:gsub('\n', '\\\n  '))))
            end
            lines[#lines + 1] = ''
        elseif node.type == 'bulletList' or node.type == 'orderedList' then
            local ordered = node.type == 'orderedList'
            local first = node.attrs and node.attrs.order or 1
            for index, item in ipairs(node.content or {}) do
                local inner = blocks(item.content, indent .. '  ')
                if not inner then
                    return nil
                end
                trim_trailing_blanks(inner)
                -- A sub-list sits right under the text it belongs to, as it does
                -- in Jira, rather than after the blank line a paragraph ends on.
                for position = #inner - 1, 1, -1 do
                    if inner[position] == '' then
                        local next_line = inner[position + 1]:sub(#indent + 3)
                        if next_line:match('^%s*[%-%*]%s') or next_line:match('^%s*%d+%.%s') then
                            table.remove(inner, position)
                        end
                    end
                end
                local marker = ordered and ('%d. '):format(first + index - 1) or '- '
                local opening = (inner[1] or ''):gsub('^%s+', '')
                lines[#lines + 1] = indent .. marker .. opening
                for position = 2, #inner do
                    lines[#lines + 1] = inner[position]
                end
            end
            lines[#lines + 1] = ''
        else
            return nil
        end
    end

    return lines
end

--- An Atlassian document as markdown. A block markdown cannot express becomes a
--- comment line, and the node itself is returned alongside so that saving can
--- put it back exactly as it was.
---@param document table?
---@return string[] lines, table<integer, table> kept
function M.to_markdown(document)
    if document == nil or document == vim.NIL then
        return { '' }, {}
    end
    if type(document) == 'string' then
        return vim.split(document, '\n', { plain = true }), {}
    end
    if type(document) ~= 'table' or document.type ~= 'doc' then
        return { '' }, {}
    end

    local lines = {}
    local kept = {}

    for _, node in ipairs(document.content or {}) do
        local rendered = blocks({ node }, '')
        if rendered then
            vim.list_extend(lines, rendered)
        else
            kept[#kept + 1] = node
            lines[#lines + 1] = PLACEHOLDER:format(#kept)
            lines[#lines + 1] = ''
        end
    end

    if #lines == 0 then
        lines[1] = ''
    end
    return lines, kept
end

--- A node as it reads, without what says nothing about its content.
---
--- localId is an editor bookmark: Jira puts one on a block the first time it is
--- touched there, and it is absent from blocks written through the API. The
--- marks on a piece of text are a set, which Jira stores in whatever order the
--- editor applied them. A numbered list without `order` starts at 1, which the
--- web editor writes out and the API leaves out. A newline inside a text node
--- shows as the same line break as a hardBreak node, so it counts as one.
---@param node any
---@return any
local function comparable(node)
    if type(node) ~= 'table' then
        return node
    end

    local copy = {}
    for field, value in pairs(node) do
        if field == 'attrs' and type(value) == 'table' then
            local attrs = {}
            for name, entry in pairs(value) do
                if name ~= 'localId' then
                    attrs[name] = entry
                end
            end
            copy.attrs = next(attrs) and attrs or nil
        else
            copy[field] = comparable(value)
        end
    end

    if type(copy.content) == 'table' then
        local split = {}
        for _, child in ipairs(copy.content) do
            if type(child) == 'table' and child.type == 'text' and child.text:find('\n', 1, true) then
                for number, line in ipairs(vim.split(child.text, '\n', { plain = true })) do
                    if number > 1 then
                        split[#split + 1] = { type = 'hardBreak' }
                    end
                    if line ~= '' then
                        split[#split + 1] = vim.tbl_extend('force', vim.deepcopy(child), { text = line })
                    end
                end
            else
                split[#split + 1] = child
            end
        end
        copy.content = split
    end

    if copy.type == 'orderedList' then
        copy.attrs = copy.attrs or {}
        copy.attrs.order = copy.attrs.order or 1
    end
    if copy.type == 'text' and copy.marks then
        table.sort(copy.marks, function(left, right)
            return left.type < right.type
        end)
    end
    return copy
end

--- The blocks that carry something. An empty paragraph is vertical space, and
--- markdown has no way to write one, so it is left out of every comparison.
---@param content table[]
---@return table[]
function M.without_blank_paragraphs(content)
    return vim.tbl_filter(function(node)
        return not (node.type == 'paragraph' and not node.content)
    end, content)
end

--- Whether this document can be edited as markdown without losing anything.
--- The check is the trip itself: render it, read it back, compare. A guess about
--- which node types are safe would be wrong the first time Jira adds one.
---@param document table?
---@return boolean faithful, table? first_lost_block
function M.round_trips(document)
    if type(document) ~= 'table' or document.type ~= 'doc' then
        return true, nil
    end

    local lines, kept = M.to_markdown(document)
    local back = M.to_adf(lines, kept)
    local original = M.without_blank_paragraphs(comparable(document.content or {}))
    local rebuilt = M.without_blank_paragraphs(comparable(back.content or {}))

    if #original ~= #rebuilt then
        return false, original[math.min(#rebuilt + 1, #original)]
    end
    for index, node in ipairs(original) do
        if not vim.deep_equal(node, rebuilt[index]) then
            return false, node
        end
    end
    return true, nil
end

--- How many blocks of a document markdown cannot express.
---@param document table?
---@return integer
function M.kept_count(document)
    local _, kept = M.to_markdown(document)
    return #kept
end

---@return string
local function local_id()
    return ('%08x%04x'):format(math.random(0, 0xffffffff), math.random(0, 0xffff))
end

--- The panel a line opens, whether it is written as an alert block or typed as
--- the slash command the Jira editor uses. `/successpanel` and `/success` both
--- mean the same thing.
---@param line string
---@return string? kind, string? inline_text
local function panel_of(line)
    local alert = line:match('^>%s*%[!(%a+)%]%s*$')
    if alert and PANELS[alert:lower()] then
        return alert:lower(), nil
    end

    local command, rest = line:match('^/(%a+)%s*(.*)$')
    if command then
        local kind = command:lower():gsub('panel$', '')
        if PANELS[kind] then
            return kind, rest
        end
    end
    return nil
end

---@type fun(lines: string[], position: integer): table, integer
local parse_list

-- Strong around em comes first, because `***x***` would otherwise read as
-- strong around `*x` and a stray star. `width` is the length of one delimiter.
local INLINE_PATTERNS = {
    { pattern = '^%*%*%*(.-)%*%*%*', marks = { 'em', 'strong' }, width = 3 },
    { pattern = '^%*%*(.-)%*%*',     marks = { 'strong' },       width = 2 },
    { pattern = '^%*(.-)%*',         marks = { 'em' },           width = 1 },
    { pattern = '^`(.-)`',           marks = { 'code' },         width = 1 },
    { pattern = '^~~(.-)~~',         marks = { 'strike' },       width = 2 },
}

---@param text string
---@return table[]
inline_nodes = function(text)
    --- The text inside a delimiter, read again for the marks nested in it, with
    --- the marks of the delimiter added to every piece.
    ---@param inner string
    ---@param marks table[]
    ---@param nested boolean false for code, whose text is never markup
    ---@return table[]
    local function marked(inner, marks, nested)
        local pieces = nested and inline_nodes(inner) or { { type = 'text', text = inner } }
        for _, piece in ipairs(pieces) do
            piece.marks = piece.marks or {}
            vim.list_extend(piece.marks, vim.deepcopy(marks))
        end
        return pieces
    end

    local nodes = {}
    local plain = {}

    local function flush()
        if #plain > 0 then
            nodes[#nodes + 1] = { type = 'text', text = table.concat(plain) }
            plain = {}
        end
    end

    local position = 1
    while position <= #text do
        local rest = text:sub(position)
        local matched = false

        local escaped = rest:match('^\\(' .. ESCAPABLE .. ')')
        if escaped then
            plain[#plain + 1] = escaped
            position = position + 2
            matched = true
        end

        -- A label holds no bracket of its own, so a `[Warning]` earlier on the
        -- line does not swallow everything up to the next real link.
        local label, href
        if not matched then
            label, href = rest:match('^%[([^%[%]]-)%]%((.-)%)')
        end
        if label then
            flush()
            vim.list_extend(nodes, marked(label, { { type = 'link', attrs = { href = href } } }, true))
            position = position + #label + #href + 4
            matched = true
        end

        if not matched then
            for _, rule in ipairs(INLINE_PATTERNS) do
                local inner = rest:match(rule.pattern)
                if inner and inner ~= '' then
                    flush()
                    local marks = {}
                    for _, mark in ipairs(rule.marks) do
                        marks[#marks + 1] = { type = mark }
                    end
                    vim.list_extend(nodes, marked(inner, marks, rule.marks[1] ~= 'code'))
                    position = position + #inner + 2 * rule.width
                    matched = true
                    break
                end
            end
        end

        if not matched then
            plain[#plain + 1] = text:sub(position, position)
            position = position + 1
        end
    end

    flush()
    return nodes
end

--- A paragraph. Several lines inside one paragraph are separated by a hardBreak,
--- which is what a soft line break is in an Atlassian document. Joining them
--- with a space instead would quietly reflow the text on every save.
---@param text string
---@return table
local function paragraph(text)
    -- Only nothing at all is an empty paragraph. A paragraph of line breaks
    -- alone is still one, and it comes back as text of nothing but newlines.
    if text == '' then
        return { type = 'paragraph' }
    end

    local content = {}
    for index, line in ipairs(vim.split(text, '\n', { plain = true })) do
        if index > 1 then
            content[#content + 1] = { type = 'hardBreak' }
        end
        vim.list_extend(content, inline_nodes(line))
    end
    return { type = 'paragraph', content = content }
end

--- Whether a line goes on in the next one: it ends on a backslash that is not
--- itself escaped, which takes an odd count of them.
---@param line string
---@return boolean
local function breaks_line(line)
    return #line:match('\\*$') % 2 == 1
end

--- The text that runs on from `first` through the lines after `position`, one
--- line per break, with `indent` taken off each line it continues on.
---@param first string
---@param lines string[]
---@param position integer the line after `first`
---@param indent string? a pattern
---@return string text, integer next_position
local function run_on(first, lines, position, indent)
    local gathered = { first }
    while breaks_line(gathered[#gathered]) and position <= #lines do
        gathered[#gathered] = gathered[#gathered]:sub(1, -2)
        gathered[#gathered + 1] = indent and lines[position]:gsub('^' .. indent, '') or lines[position]
        position = position + 1
    end
    return table.concat(gathered, '\n'), position
end

--- The indent, the kind and the text of a list line.
---@param line string?
---@return integer? indent, boolean? ordered, string? text
local function marker_of(line)
    if not line then
        return nil
    end
    -- One space after the marker and no more: the rest is the text, which can
    -- itself open on a space.
    local bullet_indent, bullet_text = line:match('^(%s*)[%-%*]%s(.*)$')
    if bullet_indent then
        return #bullet_indent, false, bullet_text
    end
    local number_indent, number_text = line:match('^(%s*)%d+%.%s(.*)$')
    if number_indent then
        return #number_indent, true, number_text
    end
    return nil
end

--- One list, and the lists nested under its items.
---@param lines string[]
---@param position integer
---@return table node, integer next_position
parse_list = function(lines, position)
    local level, ordered = marker_of(lines[position])
    local opening = lines[position]
    local items = {}

    while position <= #lines do
        local indent, kind, text = marker_of(lines[position])
        if not indent or indent < level or kind ~= ordered then
            break
        end

        position = position + 1
        local indent_of_item = ('%s'):rep(level + 2)

        -- A line ending on a backslash goes on in the next one, inside the same
        -- paragraph, the way it does outside a list.
        local opening_text
        opening_text, position = run_on(text or '', lines, position, indent_of_item)
        local item = { type = 'listItem', content = { paragraph(opening_text) } }

        --- Whether a line sits under this item rather than starting the next one:
        --- a deeper marker, or text indented past the marker.
        ---@param line string?
        ---@return boolean
        local function under_item(line)
            if not line or vim.trim(line) == '' then
                return false
            end
            local deeper = marker_of(line)
            if deeper then
                return deeper > level
            end
            return #line:match('^%s*') >= level + 2
        end

        -- Anything indented deeper belongs to this item, not to the next one. A
        -- blank line does too when the item goes on below it: that is how two
        -- paragraphs, or a paragraph and a list, sit in one item.
        local nested = {}
        while position <= #lines do
            local filled = position
            while filled <= #lines and vim.trim(lines[filled]) == '' do
                filled = filled + 1
            end
            if not under_item(lines[filled]) then
                break
            end
            for _ = position, filled - 1 do
                nested[#nested + 1] = ''
            end
            nested[#nested + 1] = lines[filled]:gsub('^' .. indent_of_item, '')
            position = filled + 1
        end

        if #nested > 0 then
            vim.list_extend(item.content, M.to_adf(nested, {}).content)
        end
        items[#items + 1] = item
    end

    if not ordered then
        return { type = 'bulletList', content = items }, position
    end
    -- The number the list opens on, the way the web editor writes it.
    return { type = 'orderedList', attrs = { order = tonumber(opening:match('^%s*(%d+)')) }, content = items },
        position
end

--- Markdown back into an Atlassian document, with the blocks set aside by
--- to_markdown put back where their comment line sits.
---@param lines string[]
---@param kept table<integer, table>?
---@return table document
function M.to_adf(lines, kept)
    kept = kept or {}
    local content = {}
    local position = 1

    ---@return string?
    local function peek()
        return lines[position]
    end

    while position <= #lines do
        local line = lines[position]
        local index = line:match(PLACEHOLDER_PATTERN)
        -- One space after the hashes and no more: the rest is the heading, which
        -- can itself open on a space.
        local heading_marks, heading_text = line:match('^(#+)%s(.*)$')
        local fence_language, fence_flags = line:match('^```(%S*)(.*)$')

        if index then
            local node = kept[tonumber(index)]
            if node then
                content[#content + 1] = node
            end
            position = position + 1
        elseif vim.trim(line) == '' then
            position = position + 1
        elseif line:match('^%-%-%-+$') then
            content[#content + 1] = { type = 'rule' }
            position = position + 1
        elseif heading_marks then
            local text
            text, position = run_on(heading_text, lines, position + 1)
            content[#content + 1] = {
                type = 'heading',
                attrs = { level = math.min(#heading_marks, 6) },
                -- An empty heading carries no content at all, as Jira writes it.
                content = paragraph(text).content,
            }
        elseif fence_language then
            position = position + 1
            local body = {}
            while position <= #lines and not (peek() or ''):match('^```') do
                body[#body + 1] = lines[position]
                position = position + 1
            end
            position = position + 1
            local attrs = {
                language = fence_language ~= '' and fence_language or nil,
                wrap = fence_flags:match('%f[%w]wrap%f[%W]') and true or nil,
            }
            content[#content + 1] = {
                type = 'codeBlock',
                attrs = next(attrs) and attrs or nil,
                content = { { type = 'text', text = table.concat(body, '\n') } },
            }
        elseif panel_of(line) then
            local kind, inline_text = panel_of(line)
            position = position + 1
            local body = {}

            if inline_text and inline_text ~= '' then
                body[#body + 1] = inline_text
            end
            -- An alert block carries its text on the quoted lines below it; a
            -- slash command carries it on the line itself and may still be
            -- continued underneath.
            -- Stop at the line that opens the next panel, rather than eating it
            -- as this one's body: two panels in a row are quoted lines either way.
            while position <= #lines and lines[position]:match('^>%s?')
                and not panel_of(lines[position]) do
                body[#body + 1] = lines[position]:gsub('^>%s?', '')
                position = position + 1
            end

            content[#content + 1] = {
                type = 'panel',
                attrs = { panelType = kind, localId = local_id() },
                content = M.to_adf(body, {}).content,
            }
        elseif line:match('^%s*[%-%*]%s+%[[ xX]%]%s') then
            local items = {}
            while position <= #lines do
                -- One space after the box and no more: the rest is the text,
                -- which can itself open on a space.
                local mark, text = lines[position]:match('^%s*[%-%*]%s+%[([ xX])%]%s(.*)$')
                if not mark then
                    break
                end
                local item_text
                item_text, position = run_on(text, lines, position + 1, '  ')
                items[#items + 1] = {
                    type = 'taskItem',
                    attrs = { localId = local_id(), state = mark == ' ' and 'TODO' or 'DONE' },
                    content = paragraph(item_text).content or {},
                }
            end
            content[#content + 1] = {
                type = 'taskList',
                attrs = { localId = local_id() },
                content = items,
            }
        elseif marker_of(line) then
            local node
            node, position = parse_list(lines, position)
            content[#content + 1] = node
        elseif line:match('^>%s?') then
            local body = {}
            while position <= #lines and (lines[position]):match('^>%s?')
                and not panel_of(lines[position]) do
                body[#body + 1] = lines[position]:gsub('^>%s?', '')
                position = position + 1
            end
            content[#content + 1] = { type = 'blockquote', content = M.to_adf(body, {}).content }
        else
            local body = {}
            while position <= #lines do
                local current = lines[position]
                -- A blank line ends the paragraph, unless the line before it
                -- marked a hard break, in which case the blank is part of it.
                local continued = #body > 0 and breaks_line(body[#body])
                if vim.trim(current) == '' and not continued then
                    break
                end
                if not continued and (current:match('^#+%s')
                        or current:match('^```')
                        or current:match('^>%s?')
                        or current:match(PLACEHOLDER_PATTERN)
                        or current:match('^%s*[%-%*]%s+')
                        or current:match('^%s*%d+%.%s+')) then
                    break
                end
                body[#body + 1] = current
                position = position + 1
            end
            for number, body_line in ipairs(body) do
                if breaks_line(body_line) then
                    body[number] = body_line:sub(1, -2)
                end
            end
            content[#content + 1] = paragraph(table.concat(body, '\n'))
        end
    end

    if #content == 0 then
        content[1] = { type = 'paragraph' }
    end
    return { type = 'doc', version = 1, content = content }
end

return M
