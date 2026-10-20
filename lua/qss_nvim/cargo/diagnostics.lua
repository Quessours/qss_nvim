-- rustc output parsed into the result of a task, so that the task list counts
-- its errors and warnings and <CR> in the log finds their files.
--
-- The errors are not placed in the buffers as diagnostics: rust-analyzer
-- already puts the same ones there.

local metadata = require('qss_nvim.cargo.metadata')

local M = {}

-- The one overseer's cargo template passes, which it does not export. rustc
-- writes the message first and the location on the line after it, and the
-- "could not compile" and "generated 1 warning" summaries are not counted.
M.ERRORFORMAT = [[%Eerror: %\%%(aborting %\|could not compile%\)%\@!%m,]]
    .. [[%Eerror[E%n]: %m,]]
    .. [[%Inote: %m,]]
    .. [[%Wwarning: %\%%(%.%# warning%\)%\@!%m,]]
    .. [[%C %#--> %f:%l:%c,]]
    .. [[%E  left:%m,%C right:%m %f:%l:%c,%Z,]]
    .. [[%.%#panicked at \'%m\'\, %f:%l:%c]]

--- The environment of a parsed cargo task. Cargo redraws its progress bar
--- with a carriage return, overseer drops the carriage return, and the bar
--- then sits in front of the `error:` that the format reads at the start of a
--- line. The colors stay.
M.ENV = { CARGO_TERM_PROGRESS_WHEN = 'never' }

--- Components to add to a task whose output is cargo output. The paths rustc
--- prints are relative to the workspace root, which is not the directory of a
--- member crate.
---@return table[]
function M.components()
    return {
        {
            'on_output_parse',
            errorformat = M.ERRORFORMAT,
            relative_file_root = metadata.workspace_root(),
        },
    }
end

--- Parse the output of overseer's own cargo tasks too. Their template already
--- sets relative_file_root for a member crate, and the component picks it up.
function M.setup()
    require('overseer').add_template_hook({ module = '^cargo$' }, function(task_defn, util)
        util.add_component(task_defn, { 'on_output_parse', errorformat = M.ERRORFORMAT })
        task_defn.env = vim.tbl_extend('force', task_defn.env or {}, M.ENV)
    end)
end

return M
