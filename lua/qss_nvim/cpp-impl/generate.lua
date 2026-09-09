local declaration = require('qss_nvim.cpp-impl.declaration')
local edit = require('qss_nvim.cpp.edit')
local indent = require('qss_nvim.cpp.indent')
local place = require('qss_nvim.cpp-impl.place')
local source = require('qss_nvim.cpp.source')
local templates = require('qss_nvim.cpp-impl.templates')
local utils = require('qss_nvim.utils')

local M = {}

local TITLE = 'C++ implementation'

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- Open a file in the window the user reads code in.
---
--- A buffer already on screen is jumped to, and a loaded buffer is put in the
--- window directly: an :edit of a file that holds unsaved changes refuses to
--- run, and the source file holds them as soon as one definition is written.
---@param path string
---@return integer bufnr
local function open(path)
    local wanted = vim.fn.bufnr(path)
    if wanted ~= -1 then
        if vim.api.nvim_get_current_buf() == wanted then
            return wanted
        end
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(win) == wanted then
                vim.api.nvim_set_current_win(win)
                return wanted
            end
        end
    end

    local main = utils.main_window()
    if main then
        vim.api.nvim_set_current_win(main)
    end

    if wanted ~= -1 and vim.api.nvim_buf_is_loaded(wanted) then
        vim.api.nvim_win_set_buf(0, wanted)
        return wanted
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
end

--- Write the definition of the declaration on a row.
---@param bufnr integer
---@param row integer 0-based
---@return boolean started
function M.run(bufnr, row)
    if not source.is_header(bufnr) then
        notify('a definition is written from the header, not from the source file',
            vim.log.levels.WARN)
        return false
    end

    local found, reason = declaration.at(bufnr, row)
    if not found then
        notify(reason or 'no declaration on this line', vim.log.levels.WARN)
        return false
    end

    source.find(bufnr, function(path)
        if not path then
            notify('no source file found for this header', vim.log.levels.ERROR)
            return
        end

        local lines = source.lines(path)
        local shown = vim.fn.fnamemodify(path, ':t')
        if not lines then
            notify(('%s cannot be read'):format(shown), vim.log.levels.ERROR)
            return
        end

        local spot = place.spot(place.definitions(lines), lines, found.scope, found.name)
        local target = open(path)

        if spot.defined then
            vim.api.nvim_win_set_cursor(0, { spot.defined + 1, 0 })
            notify(('%s is defined already\n  %s:%d'):format(found.name, shown, spot.defined + 1),
                vim.log.levels.INFO)
            return
        end

        local body_indent = indent.one_level(target)
        local written, body = templates.definition(found, spot.scope, body_indent)
        if spot.separate then
            table.insert(written, 1, '')
            body = body + 1
        end

        edit.apply(target, { { row = spot.row, lines = written } })

        local body_row = spot.row + body + 1
        vim.api.nvim_win_set_cursor(0, { body_row, #body_indent })
        notify(('%s\n  %s:%d'):format(written[body], shown, body_row), vim.log.levels.INFO)
    end)

    return true
end

return M
