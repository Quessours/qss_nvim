-- A task whose output is text given up front, with no process behind it.
--
-- It puts a report in the task list and in the output pane, so that the report
-- stays until you dispose of it, and the colors (log_colors.lua) and the <CR>
-- jumps (output_jump.lua) of a real task output apply to it as well.

local util = require('overseer.util')

---@class qss.TextStrategy
---@field lines string[]
---@field exit_code integer which status on_exit_set_status gives the task
---@field bufnr integer?
local TextStrategy = {}
TextStrategy.__index = TextStrategy

---@param opts { lines: string[]?, exit_code: integer? }?
---@return qss.TextStrategy
function TextStrategy.new(opts)
    opts = opts or {}
    return setmetatable({ lines = opts.lines or {}, exit_code = opts.exit_code or 0 }, TextStrategy)
end

function TextStrategy:reset()
    util.soft_delete_buf(self.bufnr)
    self.bufnr = nil
end

---@return integer?
function TextStrategy:get_bufnr()
    return self.bufnr
end

---@param task table
function TextStrategy:start(task)
    self.bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.lines)
    vim.bo[self.bufnr].modifiable = false
    vim.bo[self.bufnr].modified = false
    -- The task becomes running only after this returns, and an exit before
    -- that is ignored.
    vim.schedule(function()
        task:on_exit(self.exit_code)
    end)
end

function TextStrategy:stop() end

function TextStrategy:dispose()
    self:reset()
end

return TextStrategy
