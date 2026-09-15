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

---@param node table
---@return string?
local function text_of(node)
    local value = node.text or ''
    local link

    for _, mark in ipairs(node.marks or {}) do
        local wrapper = MARKS[mark.type]
        if wrapper then
            value = wrapper .. value .. wrapper
        elseif mark.type == 'link' then
            link = mark.attrs and mark.attrs.href
        else
            return nil
        end
    end

    if link then
        value = ('[%s](%s)'):format(value, link)
    end
    return value
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
            push(('%s %s'):format(('#'):rep(level), text))
            lines[#lines + 1] = ''
        elseif node.type == 'codeBlock' then
            local text = inline(node.content) or ''
            local language = node.attrs and node.attrs.language or ''
            push(('```%s'):format(language))
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
                push(('- [%s] %s'):format(done and 'x' or ' ', text))
            end
            lines[#lines + 1] = ''
        elseif node.type == 'bulletList' or node.type == 'orderedList' then
            local ordered = node.type == 'orderedList'
            for index, item in ipairs(node.content or {}) do
                local inner = blocks(item.content, indent .. '  ')
                if not inner then
                    return nil
                end
                trim_trailing_blanks(inner)
                local marker = ordered and ('%d. '):format(index) or '- '
                local first = (inner[1] or ''):gsub('^%s+', '')
                lines[#lines + 1] = indent .. marker .. first
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

--- A node as it reads, without the anchors the web editor hangs on it. localId
--- is an editor bookmark: Jira puts one on a block the first time it is touched
--- there, it is absent from blocks written through the API, and it says nothing
--- about what the block holds.
---@param node any
---@return any
local function without_anchors(node)
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
            copy[field] = without_anchors(value)
        end
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
    local original = M.without_blank_paragraphs(without_anchors(document.content or {}))
    local rebuilt = M.without_blank_paragraphs(without_anchors(back.content or {}))

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

local INLINE_PATTERNS = {
    { pattern = '^%*%*(.-)%*%*', mark = 'strong' },
    { pattern = '^%*(.-)%*',     mark = 'em' },
    { pattern = '^`(.-)`',       mark = 'code' },
    { pattern = '^~~(.-)~~',     mark = 'strike' },
}

---@param text string
---@return table[]
local function inline_nodes(text)
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

        local label, href = rest:match('^%[(.-)%]%((.-)%)')
        if label then
            flush()
            nodes[#nodes + 1] = {
                type = 'text',
                text = label,
                marks = { { type = 'link', attrs = { href = href } } },
            }
            position = position + #label + #href + 4
            matched = true
        end

        if not matched then
            for _, rule in ipairs(INLINE_PATTERNS) do
                local inner = rest:match(rule.pattern)
                if inner and inner ~= '' then
                    flush()
                    nodes[#nodes + 1] = {
                        type = 'text',
                        text = inner,
                        marks = { { type = rule.mark } },
                    }
                    local wrapper = rule.mark == 'strong' and 4
                        or rule.mark == 'strike' and 4
                        or rule.mark == 'code' and 2
                        or 2
                    position = position + #inner + wrapper
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
    if vim.trim(text) == '' then
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

--- The indent, the kind and the text of a list line.
---@param line string?
---@return integer? indent, boolean? ordered, string? text
local function marker_of(line)
    if not line then
        return nil
    end
    local bullet_indent, bullet_text = line:match('^(%s*)[%-%*]%s+(.*)$')
    if bullet_indent then
        return #bullet_indent, false, bullet_text
    end
    local number_indent, number_text = line:match('^(%s*)%d+%.%s+(.*)$')
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
    local items = {}

    while position <= #lines do
        local indent, kind, text = marker_of(lines[position])
        if not indent or indent < level or kind ~= ordered then
            break
        end

        position = position + 1
        local item = { type = 'listItem', content = { paragraph(text or '') } }

        -- Anything indented deeper belongs to this item, not to the next one.
        local nested = {}
        while position <= #lines do
            local deeper = marker_of(lines[position])
            local continuation = lines[position]:match('^%s%s+%S')
            if (deeper and deeper > level) or (not deeper and continuation) then
                local without_indent = lines[position]:gsub('^' .. ('%s'):rep(level + 2), '')
                nested[#nested + 1] = without_indent
                position = position + 1
            else
                break
            end
        end

        if #nested > 0 then
            vim.list_extend(item.content, M.to_adf(nested, {}).content)
        end
        items[#items + 1] = item
    end

    return { type = ordered and 'orderedList' or 'bulletList', content = items }, position
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
        local heading_marks, heading_text = line:match('^(#+)%s+(.*)$')
        local fence_language = line:match('^```(.*)$')

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
            content[#content + 1] = {
                type = 'heading',
                attrs = { level = math.min(#heading_marks, 6) },
                content = inline_nodes(heading_text),
            }
            position = position + 1
        elseif fence_language then
            position = position + 1
            local body = {}
            while position <= #lines and not (peek() or ''):match('^```') do
                body[#body + 1] = lines[position]
                position = position + 1
            end
            position = position + 1
            content[#content + 1] = {
                type = 'codeBlock',
                attrs = fence_language ~= '' and { language = fence_language } or nil,
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
                local mark, text = lines[position]:match('^%s*[%-%*]%s+%[([ xX])%]%s+(.*)$')
                if not mark then
                    break
                end
                items[#items + 1] = {
                    type = 'taskItem',
                    attrs = { localId = local_id(), state = mark == ' ' and 'TODO' or 'DONE' },
                    content = inline_nodes(text),
                }
                position = position + 1
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
                local continued = #body > 0 and body[#body]:match('\\$') ~= nil
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
            for index, line in ipairs(body) do
                body[index] = line:gsub('\\$', '')
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
