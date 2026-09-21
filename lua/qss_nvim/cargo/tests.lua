-- Choose tests in the picker, run them as an overseer task.
--
-- cargo nextest does the listing and the running. It reports one process per
-- test, which is what makes an exact set of tests runnable at all: `cargo test`
-- takes a substring filter, so asking for `add` also runs `add_overflows`.
--
-- Doc-tests are not here. nextest does not run them, and `cargo test --doc` is
-- a separate run with output of its own shape.

local metadata = require('qss_nvim.cargo.metadata')
local project = require('qss_nvim.cargo.project')
local state = require('qss_nvim.cargo.state')
local utils = require('qss_nvim.utils')

local cache = require('qss_nvim.cache').store('qss_cargo')

local M = {}

local TITLE = 'nextest'

M.components = {
    'on_exit_set_status',
    'on_complete_notify',
    { 'on_complete_dispose', require_view = { 'SUCCESS', 'FAILURE' } },
}

---@class qss.cargo.TestCase
---@field name string as nextest names it, module path included
---@field binary_id string the test binary it lives in
---@field crate string
---@field ignored boolean

---@class qss.cargo.Failure
---@field name string
---@field file string? where it panicked, when it panicked
---@field lnum integer?
---@field col integer?
---@field text string? the first line of what it said

---@return boolean
local function has_nextest()
    if vim.fn.executable('cargo-nextest') == 1 then
        return true
    end
    vim.notify('cargo-nextest is not installed, so no test can be listed or run\n' ..
        'cargo install cargo-nextest --locked', vim.log.levels.ERROR, { title = TITLE })
    return false
end

--- A filterset naming an exact set of tests. The binary is part of it because
--- two crates of one workspace can both declare a `tests::parses`.
---@param cases qss.cargo.TestCase[]
---@return string
local function filterset(cases)
    local terms = {}
    for _, case in ipairs(cases) do
        terms[#terms + 1] = ('(binary_id(=%s) and test(=%s))'):format(case.binary_id, case.name)
    end
    return table.concat(terms, ' or ')
end

--- `--color never` because the output is read back to find the failures, and
--- `--no-fail-fast` because nextest otherwise cancels the run at the first one,
--- which is the opposite of what a list of failures is for.
---@param cases qss.cargo.TestCase[]? nil runs everything
---@return string[]
local function run_args(cases)
    local args = { 'nextest', 'run', '--color', 'never', '--no-fail-fast' }
    vim.list_extend(args, state.nextest_args())

    if cases and #cases > 0 then
        vim.list_extend(args, { '-E', filterset(cases) })
    end
    return args
end

---@param root string?
---@return string?
local function failures_key(root)
    local workspace = metadata.workspace_root(root)
    if not workspace then
        return nil
    end
    return cache.key(workspace, 'failures')
end

--- A path as it appears in a panic message, made absolute. rustc prints it
--- relative to whichever directory cargo ran the crate in.
---@param path string
---@param root string?
---@return string?
local function resolve(path, root)
    if path:sub(1, 1) == '/' then
        if vim.fn.filereadable(path) == 1 then
            return path
        end
        return nil
    end

    local candidates = { metadata.workspace_root(root) }
    vim.list_extend(candidates, metadata.package_dirs(root))
    for _, dir in ipairs(candidates) do
        local full = dir .. '/' .. path
        if vim.fn.filereadable(full) == 1 then
            return full
        end
    end
    return nil
end

--- What failed in one run, read back out of what nextest printed.
---
--- The panic line carries the test name as the thread name, and the file and
--- line with it, so a failure that panicked needs no lookup at all. nextest
--- names every failure twice, as it happens and again in the summary, so the
--- order is kept and the repeats are dropped.
---@param lines string[]
---@param root string?
---@return qss.cargo.Failure[]
function M.parse_failures(lines, root)
    local order, seen = {}, {}
    local located = {}

    for index, line in ipairs(lines) do
        local name = line:match('^%s*FAIL%s*%[[^%]]*%]%s*%(%d+/%d+%)%s+%S+%s+([%w_:]+)')
            or line:match('^%s*FAIL%s*%[[^%]]*%]%s+%S+%s+([%w_:]+)')
        if name and not seen[name] then
            seen[name] = true
            order[#order + 1] = name
        end

        local thread, file, lnum, col =
            line:match("thread '([^']+)'.-panicked at ([^:%s]+):(%d+):(%d+)")
        if thread and not located[thread] then
            located[thread] = {
                file = resolve(file, root),
                lnum = tonumber(lnum),
                col = tonumber(col),
                text = vim.trim(lines[index + 1] or ''),
            }
            if not seen[thread] then
                seen[thread] = true
                order[#order + 1] = thread
            end
        end
    end

    local failures = {}
    for _, name in ipairs(order) do
        local where = located[name] or {}
        failures[#failures + 1] = {
            name = name,
            file = where.file,
            lnum = where.lnum,
            col = where.col,
            text = where.text,
        }
    end
    return failures
end

--- Where a test is declared, by name alone. Passing as well as failing: the
--- lookup has nothing to do with the outcome.
---@param name string a nextest test name, module path included
---@return string? file, integer? line, integer? col
function M.find_declaration(name)
    local leaf = name:match('([%w_]+)$') or name
    local root = metadata.workspace_root() or project.root()
    if not root then
        return nil
    end

    local hits = vim.fn.systemlist({
        'rg', '--vimgrep', '--no-heading', '--color', 'never',
        '-e', ('fn\\s+%s\\s*\\('):format(leaf),
        root,
    })
    if vim.v.shell_error ~= 0 or #hits == 0 then
        return nil
    end

    local file, line, col = hits[1]:match('^(.-):(%d+):(%d+):')
    return file, tonumber(line), tonumber(col)
end

--- Read the output of a finished run and remember what failed.
---@param task table
---@param root string?
local function record_failures(task, root)
    local bufnr = task.strategy and task.strategy:get_bufnr()
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local key = failures_key(root)
    if key then
        cache.set(key, M.parse_failures(lines, root))
    end
end

---@param cases qss.cargo.TestCase[]? nil runs everything
local function run(cases)
    if not has_nextest() then
        return
    end

    local overseer = require('overseer')
    local root = project.root()
    local label = cases and #cases > 0
        and ('nextest: %d selected'):format(#cases)
        or 'nextest: whole suite'

    local task = overseer.new_task({
        name = label,
        cmd = { 'cargo' },
        args = run_args(cases),
        components = M.components,
    })

    task:subscribe('on_start', function()
        local bufnr = task.strategy and task.strategy:get_bufnr()
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
            vim.keymap.set('n', 'gd', M.goto_under_cursor,
                { buffer = bufnr, desc = 'Go to the test named on this line' })
        end
    end)
    task:subscribe('on_complete', function()
        record_failures(task, root)
        return true
    end)

    overseer.open({ enter = false, direction = 'bottom' })
    vim.notify(label .. ' running...', vim.log.levels.INFO, { title = TITLE })
    task:start()
end

--- Run the whole suite, without asking anything.
function M.run_all()
    run(nil)
end

--- Jump to each failing test of the last run.
function M.failures()
    local key = failures_key()
    local stored = key and cache.get(key)
    if type(stored) ~= 'table' or #stored == 0 then
        return vim.notify('no failing tests recorded; run the suite first',
            vim.log.levels.INFO, { title = TITLE })
    end

    local items, unresolved = {}, {}
    for _, failure in ipairs(stored) do
        local file, lnum, col = failure.file, failure.lnum, failure.col
        if not file then
            file, lnum, col = M.find_declaration(failure.name)
        end

        if file then
            items[#items + 1] = {
                filename = file,
                lnum = lnum,
                col = col or 1,
                text = failure.text and ('%s  %s'):format(failure.name, failure.text)
                    or failure.name,
            }
        else
            unresolved[#unresolved + 1] = failure.name
        end
    end

    if #items > 0 then
        vim.fn.setqflist({}, ' ', { title = 'failing tests', items = items })
        vim.cmd('copen')
    end
    if #unresolved > 0 then
        vim.notify(('could not locate: %s'):format(table.concat(unresolved, ', ')),
            vim.log.levels.WARN, { title = TITLE })
    end
end

local NAME_PATTERNS = {
    '^%s*%u+%s*%[[^%]]*%]%s*%(%d+/%d+%)%s+%S+%s+([%w_:]+)', -- FAIL [ 0.0s] (1/5) bin name
    '^%s*%u+%s*%[[^%]]*%]%s+%S+%s+([%w_:]+)',               -- FAIL [ 0.0s] bin name
    '^%s*test%s+([%w_:]+)%s+%.%.%.',                        -- test name ... FAILED
    "thread '([^']+)'",                                     -- thread 'name' panicked at
}

--- The panic line carries the file and the line, so a cursor on or beside one
--- already has the answer and needs no lookup by name.
---@return string? file, integer? lnum, integer? col
local function location_near_cursor()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, math.max(row - 1, 0), row + 1, false)

    for _, line in ipairs(lines) do
        local file, lnum, col = line:match('panicked at ([^:%s]+):(%d+):(%d+)')
        if file then
            local resolved = resolve(file)
            if resolved then
                return resolved, tonumber(lnum), tonumber(col)
            end
        end
    end
    return nil
end

--- Where the test named on the current line is declared.
---@return string? file, integer? lnum, integer? col
local function declaration_near_cursor()
    local line = vim.api.nvim_get_current_line()

    local name
    for _, pattern in ipairs(NAME_PATTERNS) do
        name = line:match(pattern)
        if name then
            break
        end
    end
    name = name or vim.fn.expand('<cWORD>'):gsub('[^%w_:].*$', '')

    if name == '' then
        vim.notify('no test name on this line', vim.log.levels.WARN, { title = TITLE })
        return nil
    end

    local file, lnum, col = M.find_declaration(name)
    if not file then
        vim.notify(('could not locate %s'):format(name), vim.log.levels.WARN, { title = TITLE })
        return nil
    end
    return file, lnum, col
end

--- Jump from the current line to the code it points at.
function M.goto_under_cursor()
    local file, lnum, col = location_near_cursor()
    if not file then
        file, lnum, col = declaration_near_cursor()
    end
    if not file then
        return
    end

    -- The output lives in a pane of its own, next to the task list. The file
    -- belongs in the editor window instead of in either of them.
    local main = utils.main_window()
    if main then
        vim.api.nvim_set_current_win(main)
    else
        vim.cmd('botright split')
    end
    vim.cmd.edit(vim.fn.fnameescape(file))
    vim.api.nvim_win_set_cursor(0, { lnum or 1, (col or 1) - 1 })
end

--- The registered tests, from nextest's own JSON. Listing compiles the test
--- binaries, so the first call on a cold tree takes as long as a build.
---@param callback fun(cases: qss.cargo.TestCase[])
local function list_tests(callback)
    local cmd = { 'cargo', 'nextest', 'list', '--message-format', 'json', '--color', 'never' }
    vim.list_extend(cmd, state.nextest_args())

    vim.notify('listing tests...', vim.log.levels.INFO, { title = TITLE })
    vim.system(cmd, { cwd = project.root(), text = true }, function(result)
        local decoded
        if result.code == 0 then
            local ok, value = pcall(vim.json.decode, result.stdout)
            decoded = ok and value or nil
        end

        vim.schedule(function()
            if not (decoded and decoded['rust-suites']) then
                return vim.notify('nextest could not list the tests; does the crate compile?',
                    vim.log.levels.ERROR, { title = TITLE })
            end

            local cases = {}
            for binary_id, suite in pairs(decoded['rust-suites']) do
                for name, case in pairs(suite.testcases or {}) do
                    cases[#cases + 1] = {
                        name = name,
                        binary_id = binary_id,
                        crate = suite['package-name'] or binary_id,
                        ignored = case.ignored or false,
                    }
                end
            end

            table.sort(cases, function(left, right)
                if left.binary_id ~= right.binary_id then
                    return left.binary_id < right.binary_id
                end
                return left.name < right.name
            end)
            callback(cases)
        end)
    end)
end

--- Pick tests to run. <Tab> selects more than one; confirming with none
--- selected runs the entry under the cursor.
function M.pick()
    if not has_nextest() then
        return
    end

    list_tests(function(cases)
        if #cases == 0 then
            return vim.notify('no tests registered', vim.log.levels.WARN, { title = TITLE })
        end

        local items = { { text = 'all tests', all = true, idx = 1 } }
        for index, case in ipairs(cases) do
            local suffix = ''
            if case.ignored then
                suffix = '  [ignored]'
            end
            items[#items + 1] = {
                text = ('%s  %s%s'):format(case.crate, case.name, suffix),
                case = case,
                idx = index + 1,
            }
        end

        Snacks.picker({
            source = 'cargo_tests',
            items = items,
            format = 'text',
            title = 'nextest',
            actions = {
                goto_declaration = function(picker, item)
                    if not (item and item.case) then
                        return
                    end
                    picker:close()

                    local file, lnum, col = M.find_declaration(item.case.name)
                    if not file then
                        vim.notify(('could not locate %s'):format(item.case.name),
                            vim.log.levels.WARN, { title = TITLE })
                        return
                    end
                    vim.cmd.edit(file)
                    vim.api.nvim_win_set_cursor(0, { lnum, (col or 1) - 1 })
                end,
            },
            win = {
                input = { keys = { ['<c-]>'] = { 'goto_declaration', mode = { 'n', 'i' } } } },
                list = { keys = { ['<c-]>'] = 'goto_declaration' } },
            },
            confirm = function(picker)
                local selected = picker:selected({ fallback = true })
                picker:close()

                local chosen = {}
                for _, item in ipairs(selected) do
                    if item.all then
                        return run(nil)
                    end
                    chosen[#chosen + 1] = item.case
                end
                run(chosen)
            end,
        })
    end)
end

return M
