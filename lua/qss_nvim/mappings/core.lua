--- Half page scroll that recenters only when the view really moved. Within half
--- a page of either end of the buffer, <C-d> and <C-u> move the cursor without
--- changing the top line, and an unconditional zz there drags the viewport by
--- half a page while the cursor stays put, which reads as a recenter instead of
--- a scroll.
local function scroll_and_center(key)
    local keys = vim.keycode(key)
    return function()
        local count = vim.v.count > 0 and tostring(vim.v.count) or ""
        local topline_before = vim.fn.line("w0")
        vim.cmd("normal! " .. count .. keys)
        local scrolled = vim.fn.line("w0") ~= topline_before
        if scrolled then
            vim.cmd("normal! zz")
        end
    end
end

local M = {
    n = {
        ["<leader>af"] = { vim.lsp.buf.format, "Autoformat" },
        ["gb"] = { "<C-O>", "Go back" },
        ["<C-d>"] = { scroll_and_center("<C-d>"), "Half page down" },
        ["<C-u>"] = { scroll_and_center("<C-u>"), "Half page up" },
        ["n"] = { "nzzzv" },
        ["N"] = { "Nzzzv" }
    }
}

return M
