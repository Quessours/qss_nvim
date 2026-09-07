-- Overseer loads components by name from every lua/overseer/component/ on the
-- runtimepath, this one included.
--
-- It does what overseer's own on_result_diagnostics does, in one namespace
-- shared by every build. Overseer names its namespace after the task, and the
-- three ways a build starts here (:CMakeBuild, the "cmake build" template, the
-- build ahead of a test run) carry three different names, so a build started
-- one way would leave the errors of a build started another way on screen.
--
-- The diagnostics therefore say what the last build said, whichever path ran
-- it. They go when the next build starts, and not when the task that produced
-- them is disposed: an error nobody has fixed yet is still an error.

local util = require('overseer.util')

local NAMESPACE = 'qss_build_diagnostics'

local TYPE_TO_SEVERITY = {
    E = vim.diagnostic.severity.ERROR,
    W = vim.diagnostic.severity.WARN,
    I = vim.diagnostic.severity.INFO,
    N = vim.diagnostic.severity.INFO,
}

--- Quickfix items, as vim.diagnostic wants them.
---@param items table[]
---@param source string
---@return table[]
local function to_diagnostics(items, source)
    local converted = {}
    for _, item in ipairs(items) do
        local lnum = (item.lnum or 1) - 1
        local end_lnum
        if item.end_lnum and item.end_lnum > 0 then
            end_lnum = item.end_lnum - 1
        else
            end_lnum = lnum
        end
        table.insert(converted, {
            message = item.text,
            severity = TYPE_TO_SEVERITY[(item.type or ''):upper()] or vim.diagnostic.severity.ERROR,
            lnum = lnum,
            end_lnum = end_lnum,
            col = item.col or 0,
            end_col = item.end_col,
            source = source,
            code = item.code,
        })
    end
    return converted
end

return {
    desc = 'Show the diagnostics of the last build, in one namespace',
    constructor = function()
        local ns = vim.api.nvim_create_namespace(NAMESPACE)
        return {
            on_start = function()
                vim.diagnostic.reset(ns)
            end,
            on_result = function(_, task, result)
                vim.diagnostic.reset(ns)
                if not result.diagnostics or vim.tbl_isempty(result.diagnostics) then
                    return
                end

                for _, item in ipairs(result.diagnostics) do
                    if not item.filename and item.bufnr and item.bufnr ~= 0 then
                        item.filename = vim.api.nvim_buf_get_name(item.bufnr)
                    end
                end

                local by_file = util.tbl_group_by(result.diagnostics, 'filename')
                for filename, items in pairs(by_file) do
                    local bufnr = vim.fn.bufadd(filename)
                    vim.diagnostic.set(ns, bufnr, to_diagnostics(items, task.name))
                    -- A buffer that is not loaded keeps the diagnostics but
                    -- draws nothing, so the first entry into it draws them.
                    if not vim.api.nvim_buf_is_loaded(bufnr) then
                        util.set_bufenter_callback(bufnr, 'qss_build_diagnostics', function()
                            vim.diagnostic.show(ns, bufnr)
                        end)
                    end
                end
            end,
        }
    end,
}
