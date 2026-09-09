local declaration = require('qss_nvim.cpp-impl.declaration')
local place = require('qss_nvim.cpp-impl.place')
local source = require('qss_nvim.cpp.source')

local M = {}

M.COMMAND = 'cppimpl.define'

--- One action per declaration overlapping the range that the source file has
--- no definition for.
---
--- The list is built without waiting for clangd, so the sibling guess answers
--- where the definitions are. generate.run asks clangd itself, and reports the
--- definition it finds there.
---@param bufnr integer
---@param range lsp.Range
---@param uri string
---@return lsp.CodeAction[]
function M.at(bufnr, range, uri)
    if not source.is_header(bufnr) then
        return {}
    end

    local declarations = declaration.in_range(bufnr, range.start.line, range['end'].line)
    if #declarations == 0 then
        return {}
    end

    local path = source.sibling(vim.api.nvim_buf_get_name(bufnr))
    local lines = path and source.lines(path) or nil
    local definitions = lines and place.definitions(lines) or nil
    local shown = path and vim.fn.fnamemodify(path, ':t') or nil

    local actions = {}

    for _, found in ipairs(declarations) do
        local defined = false
        if lines and definitions then
            defined = place.spot(definitions, lines, found.scope, found.name).defined ~= nil
        end

        if not defined then
            local written = found.name
            if found.owner ~= '' then
                written = ('%s::%s'):format(found.owner, found.name)
            end

            local title = ('Implement %s()'):format(written)
            if shown then
                title = ('Implement %s() in %s'):format(written, shown)
            end

            actions[#actions + 1] = {
                title = title,
                kind = 'refactor.rewrite',
                command = {
                    title = 'Implement the declaration',
                    command = M.COMMAND,
                    arguments = { uri, found.first },
                },
            }
        end
    end

    return actions
end

return M
