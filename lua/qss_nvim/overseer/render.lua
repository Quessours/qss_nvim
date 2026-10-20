-- How a task looks in the task list: overseer's standard view, with the errors
-- and warnings its output parser found next to the name.
--
-- The standard view prints the result as `Result: diagnostics=<table>`, which
-- says nothing. A task with no parser has no diagnostics in its result and
-- shows no count, which is different from a build that found none.

local render = require('overseer.render')

local M = {}

--- Items without a type count as errors, as they do in qss_build_diagnostics.
---@param items table[]
---@return integer errors
---@return integer warnings
local function count(items)
    local errors, warnings = 0, 0
    for _, item in ipairs(items) do
        local kind = (item.type or 'E'):upper()
        if kind == 'E' then
            errors = errors + 1
        elseif kind == 'W' then
            warnings = warnings + 1
        end
    end
    return errors, warnings
end

---@param amount integer
---@param noun string
---@param hl string the highlight when there is at least one
---@return table
local function chunk(amount, noun, hl)
    local text = ('%d %s%s'):format(amount, noun, amount == 1 and '' or 's')
    return { text, amount > 0 and hl or 'Comment' }
end

---@param task table
---@return table[]
local function name_line(task)
    local line = render.status_and_name(task)
    local items = task.result and task.result.diagnostics
    if not items then
        return line
    end

    local errors, warnings = count(items)
    vim.list_extend(line, {
        { '  ' },
        chunk(errors, 'error', 'DiagnosticError'),
        { ', ', 'Comment' },
        chunk(warnings, 'warning', 'DiagnosticWarn'),
    })
    return line
end

--- The result, without the diagnostics that the name line already counts.
---@param task table
---@return table[]
local function other_results(task)
    local rest = vim.deepcopy(task.result or {})
    rest.diagnostics = nil
    return render.result_lines({ result = rest }, { oneline = true })
end

---@param task table
---@return table[]
function M.task(task)
    local lines = { name_line(task) }
    vim.list_extend(lines, render.source_lines(task))
    table.insert(lines,
        render.join(render.duration(task), render.time_since_completed(task, { hl_group = 'Comment' })))
    vim.list_extend(lines, other_results(task))
    vim.list_extend(lines, render.output_lines(task, { num_lines = 1 }))
    return render.remove_empty_lines(lines)
end

return M
