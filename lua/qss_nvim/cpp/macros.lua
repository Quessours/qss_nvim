local text = require('qss_nvim.cpp.text')

local balanced = text.balanced

local M = {}

--- The last row of the declarative Qt macro a row opens, such as Q_OBJECT or
--- Q_ENUM(Mode). `Q_INVOKABLE void ping()` carries a real declaration, so it
--- fails this test.
---@param code string[] the code lines, comments already blanked
---@param row integer 1-based
---@param identifier string the first word on that row
---@param rest_at integer the byte index after it
---@return integer? last_row 1-based
function M.last_row(code, row, identifier, rest_at)
    local starts_qt = identifier:match('^Q_') or identifier:match('^QML_')
    if not starts_qt or identifier:upper() ~= identifier then
        return nil
    end

    local line = code[row]
    local last_row, tail = row, line:sub(rest_at)
    local open = line:find('%(', rest_at)

    if open and vim.trim(line:sub(rest_at, open - 1)) == '' then
        local end_row, end_col = balanced(code, row, open)
        if not end_row then
            return nil
        end
        last_row, tail = end_row, code[end_row]:sub(end_col + 1)
    end

    local leftover = (vim.trim(tail):gsub(';', ''))
    if leftover ~= '' then
        return nil
    end
    return last_row
end

--- Every row a declarative macro occupies.
---@param lines string[]
---@return table<integer, true> rows 0-based
function M.rows(lines)
    local code = text.code_lines(lines)
    local rows = {}
    local index = 1

    while index <= #code do
        local consumed = index
        local identifier, rest_at = code[index]:match('^%s*([%a_][%w_]*)()')

        if identifier then
            local last_row = M.last_row(code, index, identifier, rest_at)
            if last_row then
                for row = index, last_row do
                    rows[row - 1] = true
                end
                consumed = last_row
            end
        end

        index = consumed + 1
    end

    return rows
end

--- The lines as one string, with every declarative macro row emptied. The rows
--- keep their numbers, so a position in the tree still points at the buffer.
---@param lines string[]
---@param rows table<integer, true>? the answer of M.rows, when it is at hand
---@return string
function M.blanked(lines, rows)
    rows = rows or M.rows(lines)

    local kept = {}
    for index, line in ipairs(lines) do
        kept[index] = rows[index - 1] and '' or line
    end
    return table.concat(kept, '\n')
end

return M
