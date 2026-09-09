local structure = require('qss_nvim.cpp.structure')

local M = {}

--- The extensions an implementation file uses, in the order they are tried.
local EXTENSIONS = { '.cpp', '.cc', '.cxx' }

--- The extensions a header uses.
local HEADERS = { ['h'] = true, ['hpp'] = true, ['hh'] = true, ['hxx'] = true, ['inl'] = true }

--- True for a buffer holding a header. A .cpp has no matching source file of
--- its own: switchSourceHeader would answer with the header and send a
--- definition back where the declaration is.
---@param bufnr integer
---@return boolean
function M.is_header(bufnr)
    local extension = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':e')
    return HEADERS[extension:lower()] == true
end

--- The file next to a header with the same stem.
---@param header string
---@return string? path
local function sibling(header)
    local stem = header:gsub('%.[^.]+$', '')
    for _, extension in ipairs(EXTENSIONS) do
        local candidate = stem .. extension
        if vim.fn.filereadable(candidate) == 1 then
            return candidate
        end
    end
    return nil
end

M.sibling = sibling

--- The lines of a file, from its buffer when it has one, so that a definition
--- written but not yet saved still counts.
---@param path string
---@return string[]?
function M.lines(path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    return vim.fn.readfile(path)
end

--- The implementation file for a header. clangd knows the answer for a file in
--- the compilation database. The sibling guess covers everything else.
---@param bufnr integer
---@param on_result fun(path: string?)
function M.find(bufnr, on_result)
    local header = vim.api.nvim_buf_get_name(bufnr)
    local clangd = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })[1]
    local method = 'textDocument/switchSourceHeader'

    if not clangd or not clangd:supports_method(method) then
        return on_result(sibling(header))
    end

    clangd:request(method, vim.lsp.util.make_text_document_params(bufnr), function(err, result)
        if err or not result then
            return on_result(sibling(header))
        end
        local path = vim.uri_to_fname(result)
        if vim.fn.filereadable(path) ~= 1 then
            return on_result(sibling(header))
        end
        on_result(path)
    end, bufnr)
end

---@class qss.cpp.Definition
---@field name string the declared name, for the already-defined test
---@field definition (fun(qualified: string): string[])?

--- Append definitions to a file, after one blank line.
---
--- A loaded buffer is edited in place, so that the user's undo history and
--- 'fixeol' behave normally. Everything else goes through readfile and
--- writefile, which is what qt-class/cmake.lua already does.
---@param path string
---@param qualified string
---@param members qss.cpp.Definition[]
---@return integer written, string? reason
function M.write(path, qualified, members)
    local defined = structure.defined_names(path)

    local segments = vim.split(qualified, '::', { plain = true })
    local class_name = segments[#segments]

    local lines = {}
    local written = 0
    for _, member in ipairs(members) do
        local key = ('%s::%s'):format(class_name, member.name)
        if member.definition and not defined[key] then
            if #lines > 0 then
                lines[#lines + 1] = ''
            end
            for _, line in ipairs(member.definition(qualified)) do
                lines[#lines + 1] = line
            end
            written = written + 1
        end
    end

    if written == 0 then
        return 0, nil
    end

    local shown = vim.fn.fnamemodify(path, ':t')
    local bufnr = vim.fn.bufnr(path)
    local loaded = bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)

    if loaded then
        if vim.bo[bufnr].modified then
            return 0, ('%s holds unsaved changes; left alone'):format(shown)
        end
        local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local tail = {}
        if #existing > 0 and vim.trim(existing[#existing]) ~= '' then
            tail[#tail + 1] = ''
        end
        vim.list_extend(tail, lines)
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, tail)
        return written, nil
    end

    if vim.fn.filereadable(path) ~= 1 then
        return 0, ('%s does not exist; only the header was changed'):format(shown)
    end

    local existing = vim.fn.readfile(path)
    if #existing > 0 and vim.trim(existing[#existing]) ~= '' then
        existing[#existing + 1] = ''
    end
    vim.list_extend(existing, lines)

    if vim.fn.writefile(existing, path) ~= 0 then
        return 0, ('could not write %s'):format(shown)
    end
    vim.cmd.checktime()
    return written, nil
end

return M
