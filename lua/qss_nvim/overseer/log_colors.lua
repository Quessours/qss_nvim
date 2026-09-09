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

local ns = vim.api.nvim_create_namespace('qss_log_colors')

--- Width the terminal was last seen wrapping at, per buffer, for the stretches
--- when a task runs with no window on its output.
---@type table<integer, integer>
local last_width = {}

---@param bufnr integer
---@return number width at which a row is a wrap, or math.huge when none wraps
local function wrap_width(bufnr)
    if vim.bo[bufnr].buftype ~= 'terminal' then
        return math.huge
    end
    local windows = vim.fn.win_findbuf(bufnr)
    if windows[1] then
        local window = vim.fn.getwininfo(windows[1])[1]
        if window then
            last_width[bufnr] = window.width - window.textoff
        end
    end
    if last_width[bufnr] then
        return last_width[bufnr]
    end
    return vim.o.columns
end

---@param bufnr integer
---@param row integer
---@return string|nil highlight group the row already carries
local function marked_level(bufnr, row)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 },
        { details = true, limit = 1 })
    if not marks[1] then
        return nil
    end
    return marks[1][4].hl_group
end

--- Colors the rows the terminal just wrote, reflowed or scrolled.
---@param bufnr integer
---@param first integer first changed row
---@param last integer row after the last changed row
local function recolor(bufnr, first, last)
    local width = wrap_width(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)

    local carry
    if first > 0 then
        local above = vim.api.nvim_buf_get_lines(bufnr, first - 1, first, false)[1]
        if above and vim.api.nvim_strwidth(above) >= width then
            carry = marked_level(bufnr, first - 1)
        end
    end

    vim.api.nvim_buf_clear_namespace(bufnr, ns, first, last)
    for index, line in ipairs(lines) do
        local hl = level_of(line) or carry
        if hl and line ~= '' then
            vim.api.nvim_buf_set_extmark(bufnr, ns, first + index - 1, 0, {
                end_col = #line,
                hl_group = hl,
            })
        end
        if vim.api.nvim_strwidth(line) >= width then
            carry = hl
        else
            carry = nil
        end
    end
end

---@type table<integer, true>
local attached = {}

---@param bufnr integer
local function attach(bufnr)
    if attached[bufnr] then
        return
    end
    attached[bufnr] = true
    recolor(bufnr, 0, vim.api.nvim_buf_line_count(bufnr))
    vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function(_, buf, _, first, _, new_last)
            if not vim.api.nvim_buf_is_valid(buf) then
                return true
            end
            recolor(buf, first, new_last)
        end,
        on_detach = function(_, buf)
            attached[buf] = nil
            last_width[buf] = nil
        end,
    })
end

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

    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'OverseerOutput',
        desc = 'Color the log levels in the output of a task',
        callback = function(args)
            attach(args.buf)
        end,
    })
end

return M
