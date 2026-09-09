local M = {}

--- The code on a line, without comments. `in_block` carries an unterminated
--- /* across lines.
---@param line string
---@param in_block boolean
---@return string code, boolean in_block
local function code_of(line, in_block)
    local pieces = {}
    local index = 1

    while index <= #line do
        if in_block then
            local close = line:find('*/', index, true)
            if not close then
                return table.concat(pieces), true
            end
            in_block = false
            index = close + 2
        else
            local block = line:find('/*', index, true)
            local rest = line:find('//', index, true)
            if rest and (not block or rest < block) then
                pieces[#pieces + 1] = line:sub(index, rest - 1)
                return table.concat(pieces), false
            end
            if not block then
                pieces[#pieces + 1] = line:sub(index)
                return table.concat(pieces), false
            end
            pieces[#pieces + 1] = line:sub(index, block - 1)
            in_block = true
            index = block + 2
        end
    end
    return table.concat(pieces), in_block
end

--- Every line with its comments blanked out, so that a parenthesis inside a
--- comment cannot upset the walk.
---@param lines string[]
---@return string[]
local function code_lines(lines)
    local out, in_block = {}, false
    for index, line in ipairs(lines) do
        out[index], in_block = code_of(line, in_block)
    end
    return out
end

--- Walk from an opening parenthesis to the one that closes it.
---@param code string[]
---@param row integer 1-based index into `code`
---@param col integer byte index of the '(' on that line
---@return integer? end_row, integer? end_col, string inner
local function balanced(code, row, col)
    local depth = 0
    local pieces = {}

    for scan = row, #code do
        local line = code[scan]
        local from = (scan == row) and col or 1
        for at = from, #line do
            local char = line:sub(at, at)
            if char == '(' then
                depth = depth + 1
                if depth > 1 then
                    pieces[#pieces + 1] = char
                end
            elseif char == ')' then
                depth = depth - 1
                if depth == 0 then
                    return scan, at, table.concat(pieces)
                end
                pieces[#pieces + 1] = char
            elseif depth >= 1 then
                pieces[#pieces + 1] = char
            end
        end
        pieces[#pieces + 1] = ' '
    end
    return nil, nil, table.concat(pieces)
end

M.code_of = code_of
M.code_lines = code_lines
M.balanced = balanced

--- Split on spaces outside <> and (), so that a template argument list and a
--- parenthesized argument each stay one token.
---@param inner string
---@return string[]
local function tokens_of(inner)
    local tokens = {}
    local current = {}
    local angle, paren = 0, 0

    local function flush()
        if #current > 0 then
            tokens[#tokens + 1] = table.concat(current)
            current = {}
        end
    end

    for at = 1, #inner do
        local char = inner:sub(at, at)
        if char == '<' then
            angle = angle + 1
        elseif char == '>' then
            angle = math.max(0, angle - 1)
        elseif char == '(' then
            paren = paren + 1
        elseif char == ')' then
            paren = math.max(0, paren - 1)
        end

        local nested = angle > 0 or paren > 0
        if char:match('%s') and not nested then
            flush()
        else
            current[#current + 1] = char
        end
    end

    flush()
    return tokens
end

M.tokens_of = tokens_of

return M
