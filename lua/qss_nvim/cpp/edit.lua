local M = {}

---@class qss.cpp.Insertion
---@field row integer 0-based row to insert before
---@field lines string[]

--- One insertion per row, holding the lines in the order they were planned.
---@param insertions qss.cpp.Insertion[]
---@return qss.cpp.Insertion[]
local function merged(insertions)
    local order, by_row = {}, {}

    for _, insertion in ipairs(insertions) do
        if #insertion.lines > 0 then
            local existing = by_row[insertion.row]
            if not existing then
                existing = { row = insertion.row, lines = {} }
                by_row[insertion.row] = existing
                order[#order + 1] = existing
            end
            for _, line in ipairs(insertion.lines) do
                existing.lines[#existing.lines + 1] = line
            end
        end
    end

    table.sort(order, function(left, right)
        return left.row > right.row
    end)
    return order
end

---@param bufnr integer
---@param insertions qss.cpp.Insertion[]
function M.apply(bufnr, insertions)
    for _, insertion in ipairs(merged(insertions)) do
        vim.api.nvim_buf_set_lines(bufnr, insertion.row, insertion.row, false, insertion.lines)
    end
end

--- The same work on a list of lines, for a file with no buffer.
---@param lines string[]
---@param insertions qss.cpp.Insertion[]
---@return string[]
function M.applied(lines, insertions)
    local out = vim.deepcopy(lines)
    for _, insertion in ipairs(merged(insertions)) do
        for offset, line in ipairs(insertion.lines) do
            table.insert(out, insertion.row + offset, line)
        end
    end
    return out
end

return M
