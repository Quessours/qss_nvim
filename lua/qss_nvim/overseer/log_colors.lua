-- Colors the output of a running program by log level, in two layers.
--
-- Layer one is the program itself. `qWarning() << "x"` prints a bare "x", so
-- nothing in the stream says which level it came from, and no pattern on this
-- side can recover it. QT_MESSAGE_PATTERN fixes that at the source: Qt reads it
-- at startup and picks one branch per message. Programs built on env_logger,
-- tracing or a spdlog color sink already color themselves once they see a tty,
-- which the pty behind an overseer task gives them.
--
-- Layer two is the RULES table below, for output that names its level in plain
-- text ("[error]", "level=warn", "ERROR:"). Editor highlighting wins over
-- terminal colors (see :help terminal), so a line that arrives with escape
-- codes of its own still ends up the color the rule asks for.

local M = {}

-- 256-color codes rather than the 8-color names, because "orange" is not one of
-- the eight and terminal_color_3 is whatever the colorscheme made of yellow.
local ANSI = {
    debug = '\27[38;5;244m',
    info = '\27[38;5;39m',
    warning = '\27[38;5;208m',
    critical = '\27[38;5;196m',
    fatal = '\27[1;38;5;196m',
    reset = '\27[0m',
}

local HL = {
    QssLogDebug = '#8a8f98',
    QssLogInfo = '#3fa7ff',
    QssLogWarn = '#e8951f',
    QssLogError = '#e64545',
}

--- Level names appear in enough shapes that each pattern matches a delimiter
--- too: a bare "error" inside a path or a sentence is not a level, "[error]" is.
--- The uppercase patterns carry \C because uppercase is exactly what tells
--- `ERROR` in a log line apart from the word in a message body. Every pattern
--- states its case with \c or \C, since one of them anywhere applies to the
--- whole pattern, which is also why these stay separate instead of being joined
--- into one alternation.
---@type { hl: string, patterns: string[] }[]
local RULES = {
    {
        hl = 'QssLogError',
        patterns = {
            [==[\c\[\s*\%(error\|err\|fatal\|critical\|crit\)\s*\]]==],
            [==[\c\<\%(level\|lvl\|severity\)"\?\s*[=:]\s*"\?\%(error\|fatal\|critical\)\>]==],
            [==[\C\<\%(ERROR\|ERR\|FATAL\|CRITICAL\|CRIT\)\>]==],
            [==[\c\<\%(error\|fatal\)\s*:]==],
            [==[\c\<assert\%(ion\)\?\>.*\<fail]==],
            [==[\c\<sig\%(segv\|abrt\|bus\|fpe\)\>]==],
            [==[\Cpanicked at]==],
            [==[\CSegmentation fault]==],
            [==[\Cterminate called after throwing]==],
        },
    },
    {
        hl = 'QssLogWarn',
        patterns = {
            [==[\c\[\s*\%(warn\|warning\)\s*\]]==],
            [==[\c\<\%(level\|lvl\|severity\)"\?\s*[=:]\s*"\?\%(warn\|warning\)\>]==],
            [==[\C\<\%(WARN\|WARNING\)\>]==],
            [==[\c\<warning\s*:]==],
        },
    },
    {
        hl = 'QssLogInfo',
        patterns = {
            [==[\c\[\s*\%(info\|notice\)\s*\]]==],
            [==[\c\<\%(level\|lvl\|severity\)"\?\s*[=:]\s*"\?\%(info\|notice\)\>]==],
            [==[\C\<\%(INFO\|NOTICE\)\>]==],
        },
    },
    {
        hl = 'QssLogDebug',
        patterns = {
            [==[\c\[\s*\%(debug\|dbg\|trace\|verbose\)\s*\]]==],
            [==[\c\<\%(level\|lvl\|severity\)"\?\s*[=:]\s*"\?\%(debug\|trace\)\>]==],
            [==[\C\<\%(DEBUG\|DBG\|TRACE\|VERBOSE\)\>]==],
        },
    },
}

---@type { hl: string, regexes: vim.regex[] }[]|nil
local compiled

---@return { hl: string, regexes: vim.regex[] }[]
local function rules()
    if compiled then
        return compiled
    end
    compiled = {}
    for _, rule in ipairs(RULES) do
        local regexes = {}
        for _, pattern in ipairs(rule.patterns) do
            table.insert(regexes, vim.regex(pattern))
        end
        table.insert(compiled, { hl = rule.hl, regexes = regexes })
    end
    return compiled
end

--- First rule that matches wins, so RULES stays ordered by severity: a line
--- reading "WARN 0 errors" is a warning, not an error.
---@param line string
---@return string|nil highlight group
local function level_of(line)
    for _, rule in ipairs(rules()) do
        for _, regex in ipairs(rule.regexes) do
            if regex:match_str(line) then
                return rule.hl
            end
        end
    end
end

-- Exposed so a line can be checked against the rules without running a task.
M.level_of = level_of

local function define_highlights()
    for group, color in pairs(HL) do
        vim.api.nvim_set_hl(0, group, { fg = color, default = true })
    end
end

function M.setup()
    -- Every child of this nvim inherits the variable, so a Qt program colors
    -- itself whether overseer, nvim-dap or a bare :terminal started it.
    vim.env.QT_MESSAGE_PATTERN = table.concat({
        '%{if-debug}' .. ANSI.debug .. '%{endif}',
        '%{if-info}' .. ANSI.info .. '%{endif}',
        '%{if-warning}' .. ANSI.warning .. '%{endif}',
        '%{if-critical}' .. ANSI.critical .. '%{endif}',
        '%{if-fatal}' .. ANSI.fatal .. '%{endif}',
        '%{if-category}%{category}: %{endif}%{message}' .. ANSI.reset,
    })

    define_highlights()
    vim.api.nvim_create_autocmd('ColorScheme', {
        desc = 'Keep the log level colors after a colorscheme change',
        callback = define_highlights,
    })

    local ns = vim.api.nvim_create_namespace('qss_log_colors')
    vim.api.nvim_set_decoration_provider(ns, {
        -- Returning false keeps on_line out of every other buffer being drawn.
        -- b:overseer_task is set on task output buffers only.
        on_win = function(_, _, bufnr)
            return vim.b[bufnr].overseer_task ~= nil
        end,
        on_line = function(_, _, bufnr, row)
            local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
            if not line or line == '' then
                return
            end
            local hl = level_of(line)
            if not hl then
                return
            end
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                end_col = #line,
                hl_group = hl,
                ephemeral = true,
            })
        end,
    })
end

return M
