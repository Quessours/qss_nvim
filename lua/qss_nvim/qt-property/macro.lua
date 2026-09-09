local macros = require('qss_nvim.cpp.macros')
local text = require('qss_nvim.cpp.text')

local M = {}

local balanced = text.balanced
local code_lines = text.code_lines
local tokens_of = text.tokens_of

--- Attributes that take a value, mapped to their field on the record.
local VALUED = {
    READ = 'read',
    WRITE = 'write',
    MEMBER = 'member',
    RESET = 'reset',
    NOTIFY = 'notify',
    BINDABLE = 'bindable',
    REVISION = 'revision',
    DESIGNABLE = 'designable',
    SCRIPTABLE = 'scriptable',
    STORED = 'stored',
    USER = 'user',
}

--- Attributes that stand alone.
local FLAGS = { CONSTANT = 'constant', FINAL = 'final', REQUIRED = 'required' }

--- How far above the cursor a wrapped macro is still looked for.
local LOOKBACK = 12

M.VALUED = VALUED
M.FLAGS = FLAGS

--- The attribute a token opens, and the value the token carries itself.
--- REVISION(1, 2) is the only attribute whose value lives inside the token.
---@param token string
---@return string? keyword, string? value
local function attribute_of(token)
    local keyword = token:match('^([%u][%u%d_]*)')
    if not keyword or not (VALUED[keyword] or FLAGS[keyword]) then
        return nil
    end

    local rest = token:sub(#keyword + 1)
    if rest == '' then
        return keyword, nil
    end

    local inline = rest:match('^%b()$')
    if inline then
        return keyword, inline:sub(2, -2)
    end
    return nil
end

M.attribute_of = attribute_of

--- The macro's arguments on one line. A line continuation leaves a backslash
--- behind, which cannot appear in a declaration otherwise.
---@param inner string
---@return string
local function collapse(inner)
    local joined = inner:gsub('\\%s', ' '):gsub('%s+', ' ')
    return vim.trim(joined)
end

---@class qss.qt.Property
---@field type string? the type as written, whitespace normalized
---@field name string? nil for a declaration still being typed
---@field read string?
---@field write string?
---@field member string?
---@field reset string?
---@field notify string?
---@field bindable string?
---@field revision string?
---@field designable string?
---@field scriptable string?
---@field stored string?
---@field user string?
---@field constant boolean
---@field final boolean
---@field required boolean
---@field first integer 0-based row the macro starts on
---@field last integer 0-based row its closing parenthesis is on
---@field text string the macro on one line, for messages

---@class qss.qt.Problem
---@field first integer
---@field last integer
---@field text string
---@field reason string

--- Read one macro's argument list. Permissive on purpose: a half-typed
--- declaration still yields what it has, and M.validate judges the result.
---@param inner string the text between the parentheses, spaces collapsed
---@return qss.qt.Property? property, string? reason
function M.parse(inner)
    local tokens = tokens_of(inner)
    if #tokens == 0 then
        return nil, 'the argument list is empty'
    end

    local first_attribute, first_shout
    for index, token in ipairs(tokens) do
        if not first_attribute and attribute_of(token) then
            first_attribute = index
        end
        if not first_shout and token:match('^[%u][%u%d_]+$') then
            first_shout = index
        end
    end

    if first_shout and (not first_attribute or first_shout < first_attribute) then
        return nil, ('unknown attribute %s'):format(tokens[first_shout])
    end

    local head_count = (first_attribute or (#tokens + 1)) - 1
    if head_count < 1 then
        return nil, 'no type before the first attribute'
    end

    ---@type qss.qt.Property
    local property = { constant = false, final = false, required = false, first = 0, last = 0, text = '' }

    if head_count == 1 then
        property.type = tokens[1]
    else
        local name_token = tokens[head_count]
        local punctuation = name_token:match('^([%*&]+)') or ''
        local name = name_token:sub(#punctuation + 1)
        if not name:match('^[%a_][%w_]*$') then
            return nil, ('%s is not a valid property name'):format(name_token)
        end

        local head = {}
        for index = 1, head_count - 1 do
            head[index] = tokens[index]
        end

        local written = table.concat(head, ' ')
        if punctuation ~= '' then
            written = written .. ' ' .. punctuation
        end

        property.name = name
        property.type = (written:gsub(',%s*', ', '))
    end

    local index = first_attribute
    while index and index <= #tokens do
        local token = tokens[index]
        local keyword, value = attribute_of(token)

        if not keyword then
            return nil, ('unknown attribute %s'):format(token)
        elseif FLAGS[keyword] then
            property[FLAGS[keyword]] = true
            index = index + 1
        elseif value then
            ---@diagnostic disable-next-line: assign-type-mismatch
            property[VALUED[keyword]] = value
            index = index + 1
        else
            local next_token = tokens[index + 1]
            if not next_token or attribute_of(next_token) then
                return nil, ('%s needs a value'):format(keyword)
            end
            ---@diagnostic disable-next-line: assign-type-mismatch
            property[VALUED[keyword]] = next_token
            index = index + 2
        end
    end

    return property, nil
end

--- What moc would reject, and what this feature declines to generate.
---@param property qss.qt.Property
---@return string? reason
function M.validate(property)
    if not property.name then
        return 'needs a type and a name'
    end
    if property.bindable then
        return 'BINDABLE properties are not generated'
    end
    if not (property.read or property.member) then
        return 'needs READ or MEMBER'
    end
    if property.constant and property.write then
        return 'CONSTANT cannot be combined with WRITE'
    end
    if property.constant and property.notify then
        return 'CONSTANT cannot be combined with NOTIFY'
    end
    return nil
end

--- Every Q_PROPERTY in the lines, and the ones that could not be read.
---@param lines string[]
---@return qss.qt.Property[] properties, qss.qt.Problem[] problems
function M.scan(lines)
    local code = code_lines(lines)
    local properties, problems = {}, {}
    local index = 1

    while index <= #code do
        local line = code[index]
        local identifier, rest_at = line:match('^%s*([%a_][%w_]*)()')
        local consumed = index

        if identifier == 'Q_PROPERTY' then
            local open = line:find('%(', rest_at)
            if not open then
                problems[#problems + 1] = {
                    first = index - 1,
                    last = index - 1,
                    text = vim.trim(line),
                    reason = 'Q_PROPERTY without an argument list',
                }
            else
                local end_row, _, inner = balanced(code, index, open)
                local text = ('Q_PROPERTY(%s)'):format(collapse(inner))

                if not end_row then
                    problems[#problems + 1] = {
                        first = index - 1,
                        last = #code - 1,
                        text = text,
                        reason = 'unterminated Q_PROPERTY',
                    }
                    consumed = #code
                else
                    local property, reason = M.parse(collapse(inner))
                    if property then
                        property.first, property.last = index - 1, end_row - 1
                        property.text = text
                        properties[#properties + 1] = property
                    else
                        problems[#problems + 1] = {
                            first = index - 1,
                            last = end_row - 1,
                            text = text,
                            reason = reason or 'could not be read',
                        }
                    end
                    consumed = end_row
                end
            end
        elseif identifier then
            consumed = macros.last_row(code, index, identifier, rest_at) or index
        end

        index = consumed + 1
    end

    return properties, problems
end

--- The property whose macro covers a row.
---@param properties qss.qt.Property[]
---@param row integer 0-based
---@return qss.qt.Property?
function M.at_row(properties, row)
    for _, property in ipairs(properties) do
        if row >= property.first and row <= property.last then
            return property
        end
    end
    return nil
end

---@class qss.qt.Cursor
---@field slot 'type'|'name'|'keyword'|'value'
---@field keyword string? the attribute whose value the cursor sits on
---@field word string the partial word before the cursor
---@field word_col integer 0-based byte column the word starts at
---@field macro_row integer 0-based row the macro starts on
---@field property qss.qt.Property? what the text before the cursor says

---@param bufnr integer
---@param row integer 0-based
---@param col integer 0-based byte column
---@return qss.qt.Cursor?
local function compute_cursor(bufnr, row, col)
    local from = math.max(0, row - LOOKBACK)
    local lines = vim.api.nvim_buf_get_lines(bufnr, from, row + 1, false)
    if #lines == 0 then
        return nil
    end

    lines[#lines] = lines[#lines]:sub(1, col)
    local code = code_lines(lines)

    local start_row, start_col
    local index = 1
    while index <= #code do
        local at = code[index]:find('Q_PROPERTY%s*%(')
        local open = at and code[index]:find('%(', at)
        if open then
            local end_row = balanced(code, index, open)
            if not end_row then
                start_row, start_col = index, open
                break
            end
            index = end_row
        end
        index = index + 1
    end

    if not start_row then
        return nil
    end

    local pieces = {}
    for scan = start_row, #code do
        local line = code[scan]
        pieces[#pieces + 1] = (scan == start_row) and line:sub(start_col + 1) or line
        pieces[#pieces + 1] = ' '
    end
    local prefix = table.concat(pieces):sub(1, -2)

    local tokens = tokens_of(prefix)
    local word = ''
    if not prefix:match('%s$') and #tokens > 0 then
        word = tokens[#tokens]
        tokens[#tokens] = nil
    end

    local slot, keyword
    local last = tokens[#tokens]
    local last_keyword, inline = nil, nil
    if last then
        last_keyword, inline = attribute_of(last)
    end

    if last_keyword and VALUED[last_keyword] and not inline then
        slot, keyword = 'value', last_keyword
    elseif #tokens == 0 then
        slot = 'type'
    elseif #tokens == 1 then
        slot = 'name'
    else
        slot = 'keyword'
    end

    local head = tokens
    if slot == 'value' then
        head = {}
        for index = 1, #tokens - 1 do
            head[index] = tokens[index]
        end
    end
    local property = M.parse(table.concat(head, ' '))

    return {
        slot = slot,
        keyword = keyword,
        word = word,
        word_col = col - #word,
        macro_row = from + start_row - 1,
        property = property,
    }
end

local memo_key, memo_value

--- Which argument slot a position sits in. Memoized, because a completion
--- filter can ask once per candidate item.
---@param bufnr integer
---@param row integer 0-based
---@param col integer 0-based byte column
---@return qss.qt.Cursor?
function M.cursor(bufnr, row, col)
    local key = ('%d:%d:%d:%d'):format(bufnr, vim.b[bufnr].changedtick or 0, row, col)
    if key == memo_key then
        return memo_value
    end
    memo_key, memo_value = key, compute_cursor(bufnr, row, col)
    return memo_value
end

return M
