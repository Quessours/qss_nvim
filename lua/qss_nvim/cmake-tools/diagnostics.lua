-- Compiler output as diagnostics: a build error lands on the line that caused
-- it, instead of staying in the overseer pane as text to read and scroll.
--
-- The $gcc matcher reads the "file:line:col: error: message" shape, which gcc,
-- clang and moc all print. qmllint prints the level first instead:
-- "Warning: /abs/File.qml:12:5: message [category]".

local state = require('qss_nvim.cmake-tools.state')

local M = {}

-- Only the qmllint levels that make a lint target fail. Its "Info:" lines are
-- hints about compiling QML to C++, and a large project prints thousands.
local QMLLINT = {
    {
        severity = 'warning',
        pattern = {
            vim_regexp = [[\v^Warning: (.{-}):(\d+):(\d+): (.*)$]],
            file = 1,
            line = 2,
            column = 3,
            message = 4,
        },
    },
    {
        severity = 'error',
        pattern = {
            vim_regexp = [[\v^%(Critical|Error): (.{-}):(\d+):(\d+): (.*)$]],
            file = 1,
            line = 2,
            column = 3,
            message = 4,
        },
    },
}

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
    local root = relative_root()
    return {
        {
            'on_output_parse',
            problem_matcher = { '$gcc', QMLLINT[1], QMLLINT[2] },
            relative_file_root = root,
        },
        'qss_build_diagnostics',
        { 'qss_build_failures', relative_file_root = root },
    }
end

--- The same, for a task someone else created.
---@param task table
function M.attach(task)
    task:add_components(M.components())
end

return M
