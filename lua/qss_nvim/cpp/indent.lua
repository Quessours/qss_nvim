local M = {}

--- One indentation level, from the buffer's own options.
---@param bufnr integer
---@return string
function M.one_level(bufnr)
    if not vim.bo[bufnr].expandtab then
        return '\t'
    end
    local width = vim.bo[bufnr].shiftwidth
    if width == 0 then
        width = vim.bo[bufnr].tabstop
    end
    return (' '):rep(width)
end

--- How far in the members of the class sit.
---@param bufnr integer
---@param class qss.cpp.ClassInfo
---@param section qss.cpp.Section?
---@return string
function M.member(bufnr, class, section)
    if section and section.indent then
        return section.indent
    end
    for _, other in ipairs(class.sections) do
        if other.indent then
            return other.indent
        end
    end
    local line = vim.api.nvim_buf_get_lines(bufnr, class.node:start(), class.node:start() + 1, false)[1]
    return (line and line:match('^%s*') or '') .. M.one_level(bufnr)
end

--- How far in the section labels sit.
---@param bufnr integer
---@param class qss.cpp.ClassInfo
---@return string
function M.label(bufnr, class)
    for _, section in ipairs(class.sections) do
        if section.label_row then
            local line = vim.api.nvim_buf_get_lines(bufnr, section.label_row, section.label_row + 1, false)[1]
            return line and line:match('^%s*') or ''
        end
    end
    local line = vim.api.nvim_buf_get_lines(bufnr, class.node:start(), class.node:start() + 1, false)[1]
    return line and line:match('^%s*') or ''
end

return M
