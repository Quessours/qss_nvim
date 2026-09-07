-- Compiler output as diagnostics: a build error lands on the line that caused
-- it, instead of staying in the overseer pane as text to read and scroll.
--
-- The $gcc matcher reads the "file:line:col: error: message" shape, which gcc,
-- clang and moc all print.

local state = require('qss_nvim.cmake-tools.state')

local M = {}

--- Where a relative path in the output starts from. The generator invokes the
--- compiler from the build directory, so "../src/foo.cpp" is relative to that
--- and not to the directory nvim was started in.
---@return string
local function relative_root()
    return (vim.fs.normalize(vim.fn.fnamemodify(state.build_dir(), ':p')):gsub('/$', ''))
end

--- Components to add to a task whose output is compiler output.
---@return table[]
function M.components()
    return {
        {
            'on_output_parse',
            problem_matcher = '$gcc',
            relative_file_root = relative_root(),
        },
        'qss_build_diagnostics',
    }
end

--- The same, for a task someone else created.
---@param task table
function M.attach(task)
    task:add_components(M.components())
end

return M
