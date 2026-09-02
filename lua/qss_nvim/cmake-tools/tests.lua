-- Choose tests in the picker, run them as an overseer task.
--
local state = require('qss_nvim.cmake-tools.state')

local M = {}

M.components = {
    'on_exit_set_status',
    'on_complete_notify',
    { 'on_complete_dispose', require_view = { 'SUCCESS', 'FAILURE' } },
}

--- Anything ctest's own -R regex would read as a metacharacter.
local SPECIAL = '^$()%.[]*+-?{}|\\'

---@param name string
---@return string
local function escape(name)
    return (name:gsub('.', function(char)
        return SPECIAL:find(char, 1, true) and ('\\' .. char) or char
    end))
end

--- -R matches names by regex, so an exact set becomes an anchored alternation.
---@param names string[]
---@return string
local function names_regex(names)
    return '^(' .. table.concat(vim.tbl_map(escape, names), '|') .. ')$'
end

--- The test preset only counts if it survived the sentinel filter in state.
---@return string?
local function usable_preset()
    local selected = state.selected_preset('test')
    if selected and vim.tbl_contains(state.preset_names('test'), selected) then
        return selected
    end
    return nil
end

--- Which test set ctest acts on, and in which configuration.
---@return string[]
local function ctest_target()
    local preset = usable_preset()
    if preset then
        return { '--preset', preset }
    end
    return { '--test-dir', state.build_dir(), '-C', state.build_type() }
end

---@param names string[]? nil runs the whole suite
local function run(names)
    local args = ctest_target()

    if names and #names > 0 then
        vim.list_extend(args, { '-R', names_regex(names) })
    end
    vim.list_extend(args, { '--output-on-failure' })

    local overseer = require('overseer')
    local label = names and #names > 0
        and ('ctest: %d selected'):format(#names)
        or 'ctest: whole suite'

    local task = overseer.new_task({
        name = label,
        cmd = { 'ctest' },
        args = args,
        components = M.components,
    })
    task:subscribe('on_start', function()
        local buf = task.strategy and task.strategy:get_bufnr()
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.keymap.set('n', 'gd', M.goto_under_cursor,
                { buffer = buf, desc = 'Go to the test named on this line' })
        end
    end)

    overseer.open({ enter = false, direction = 'bottom' })
    vim.notify(label .. ' running...', vim.log.levels.INFO, { title = 'CTest' })
    task:start()
end

---@param leaf string which of ctest's records this caches
---@return string
local function cache_path(leaf)
    local key = vim.fn.sha256(state.build_dir()):sub(1, 16)
    return ('%s/nvim-ctest-%s-%s.log'):format(vim.uv.os_tmpdir() or '/tmp', leaf, key)
end

---@param path string
---@return string[]
local function read_failed(path)
    local file = io.open(path, 'r')
    if not file then
        return {}
    end

    local names = {}
    for line in file:lines() do
        local name = line:match('^%d+:(.+)$')
        if name then
            names[#names + 1] = name
        end
    end
    file:close()
    return names
end

--- Read ctest's own record, or fall back to the cached copy.
---@return string[]
local function failed_names()
    local live = state.build_dir() .. '/Testing/Temporary/LastTestsFailed.log'
    local names = read_failed(live)
    if #names > 0 then
        pcall(vim.uv.fs_copyfile, live, cache_path('failed'))
        return names
    end
    return read_failed(cache_path('failed'))
end

---@return string[]
local function transcript()
    local live = state.build_dir() .. '/Testing/Temporary/LastTest.log'
    if vim.fn.filereadable(live) == 1 then
        pcall(vim.uv.fs_copyfile, live, cache_path('output'))
        return vim.fn.readfile(live)
    end
    local cached = cache_path('output')
    if vim.fn.filereadable(cached) == 1 then
        return vim.fn.readfile(cached)
    end
    return {}
end

---@param line string?
---@return string? file, integer? lnum
local function parse_location(line)
    local file, lnum = (line or ''):match('Loc:%s*%[(.+)%((%d+)%)%]')
    if file then
        return file, tonumber(lnum)
    end
    return nil
end

--- Every failing QTest case of the last run, grouped by the binary that
--- reported it.
---@return table<string, table[]>
local function qtest_failures()
    local lines = transcript()
    local grouped = {}
    for index, line in ipairs(lines) do
        local binary, case = line:match('^FAIL!%s*:%s*([%w_]+)::(%S+)')
        if binary then
            local file, lnum = parse_location(lines[index + 1])
            if file then
                grouped[binary] = grouped[binary] or {}
                table.insert(grouped[binary], {
                    filename = file,
                    lnum = lnum,
                    col = 1,
                    text = ('%s::%s'):format(binary, case),
                })
            end
        end
    end
    return grouped
end

---@param full string
---@return string
local function declaration_pattern(full)
    local without_index = full:gsub('/%d+$', '')
    local suite, name = without_index:match('^(.*)%.([^.]+)$')
    suite = (suite or ''):gsub('^.*/', '')
    name = name or without_index

    local function quote(text)
        return (text:gsub('[%^%$%(%)%.%[%]%*%+%-%?{}|\\]', '\\%0'))
    end
    if suite == '' then
        return ('TEST\\w*\\(\\s*\\w+\\s*,\\s*%s\\s*\\)'):format(quote(name))
    end
    return ('TEST\\w*\\(\\s*%s\\s*,\\s*%s\\s*\\)'):format(quote(suite), quote(name))
end

--- Where a test is declared, by name alone. Passing as well as failing: the
--- lookup has nothing to do with the outcome.
---@param full string a ctest test name
---@return string? file, integer? line, integer? col
function M.find_declaration(full)
    local hits = vim.fn.systemlist({
        'rg', '--vimgrep', '--no-heading', '--color', 'never',
        '-e', declaration_pattern(full),
    })
    if vim.v.shell_error ~= 0 or #hits == 0 then
        return nil
    end
    local file, line, col = hits[1]:match('^(.-):(%d+):(%d+):')
    return file, tonumber(line), tonumber(col)
end

function M.failures()
    local names = failed_names()
    if #names == 0 then
        return vim.notify('no failing tests recorded; run the suite first',
            vim.log.levels.INFO, { title = 'CTest' })
    end

    local reported = qtest_failures()
    local items, unresolved = {}, {}
    for _, full in ipairs(names) do
        -- A QTest binary contributes one item per failing case, at the line
        -- QTest named, rather than one item for the binary itself.
        if reported[full] then
            vim.list_extend(items, reported[full])
        else
            local file, line, col = M.find_declaration(full)
            if file then
                items[#items + 1] = { filename = file, lnum = line, col = col, text = full }
            else
                unresolved[#unresolved + 1] = full
            end
        end
    end

    if #items > 0 then
        vim.fn.setqflist({}, ' ', { title = 'failing tests', items = items })
        vim.cmd('copen')
    end
    if #unresolved > 0 then
        vim.notify(('could not locate: %s'):format(table.concat(unresolved, ', ')),
            vim.log.levels.WARN, { title = 'CTest' })
    end
end

local NAME_PATTERNS = {
    'Test%s+#%d+:%s+([%w_%./]+)',  -- 1/2 Test #1: Suite.Name ....... Passed
    'Start%s+%d+:%s+([%w_%./]+)',  --         Start 285: Suite.Name
    '^%s*%d+%s*%-%s*([%w_%./]+)',  -- \t 21 - Suite.Name (Failed)
    '%[%s*FAILED%s*%]%s+([%w_%./]+)', -- [  FAILED  ] Suite.Name (0 ms)
    '%[%s*RUN%s*%]%s+([%w_%./]+)',    -- [ RUN      ] Suite.Name
}

--- QTest prints the failure and its location on two consecutive lines, so a
--- cursor on either one already has the answer and needs no lookup by name.
---@return string? file, integer? lnum
local function location_near_cursor()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, math.max(row - 1, 0), row + 1, false)
    for _, line in ipairs(lines) do
        local file, lnum = parse_location(line)
        if file then
            return file, lnum
        end
    end
    return nil
end

--- Where the test named on the current line is declared, by name alone.
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
    -- Fallback
    name = name or vim.fn.expand('<cWORD>'):gsub('[^%w_%./].*$', '')

    if name == '' then
        vim.notify('no test name on this line', vim.log.levels.WARN, { title = 'CTest' })
        return nil
    end

    local file, lnum, col = M.find_declaration(name)
    if not file then
        vim.notify(('could not locate %s'):format(name), vim.log.levels.WARN,
            { title = 'CTest' })
        return nil
    end
    return file, lnum, col
end

--- Jump from the current line to the code it points at.
function M.goto_under_cursor()
    local file, line_number, col = location_near_cursor()
    if not file then
        file, line_number, col = declaration_near_cursor()
    end
    if not file then
        return
    end

    -- The output usually lives in a floating pane; land in the window the picker
    -- and the quickfix list would use rather than replacing the output itself.
    local main = vim.fn.win_getid(vim.fn.winnr('#'))
    if main ~= 0 and main ~= vim.api.nvim_get_current_win() then
        vim.api.nvim_set_current_win(main)
    end
    vim.cmd.edit(file)
    vim.api.nvim_win_set_cursor(0, { line_number, (col or 1) - 1 })
end

--- Run the whole suite, without asking anything.
function M.run_all()
    run(nil)
end

--- The registered tests, from ctest's own JSON.
---@param callback fun(tests: { name: string, labels: string[] }[])
local function list_tests(callback)
    local cmd = { 'ctest' }
    vim.list_extend(cmd, ctest_target())
    cmd[#cmd + 1] = '--show-only=json-v1'

    vim.system(cmd, { text = true }, function(result)
        local decoded
        if result.code == 0 then
            local ok, value = pcall(vim.json.decode, result.stdout)
            decoded = ok and value or nil
        end

        vim.schedule(function()
            if not (decoded and decoded.tests) then
                return vim.notify('ctest could not list the tests; is the project configured?',
                    vim.log.levels.ERROR, { title = 'CTest' })
            end

            local tests = {}
            for _, item in ipairs(decoded.tests) do
                local labels = {}
                for _, property in ipairs(item.properties or {}) do
                    if property.name == 'LABELS' then
                        labels = property.value or {}
                        break
                    end
                end
                tests[#tests + 1] = { name = item.name, labels = labels }
            end
            callback(tests)
        end)
    end)
end

--- Pick tests to run. <Tab> selects more than one; confirming with none selected
--- runs the entry under the cursor.
function M.pick()
    list_tests(function(tests)
        if #tests == 0 then
            return vim.notify('no tests registered; is the project configured?',
                vim.log.levels.WARN, { title = 'CTest' })
        end

        local items = { { text = 'all tests', all = true, idx = 1 } }
        for index, test in ipairs(tests) do
            local labels = #test.labels > 0
                and ('  [%s]'):format(table.concat(test.labels, ' '))
                or ''
            items[#items + 1] = {
                text = test.name .. labels,
                name = test.name,
                idx = index + 1,
            }
        end

        Snacks.picker({
            source = 'cmake_tests',
            items = items,
            format = 'text',
            title = 'ctest',
            actions = {
                goto_declaration = function(picker, item)
                    if not (item and item.name) then
                        return
                    end
                    picker:close()
                    local file, line, col = M.find_declaration(item.name)
                    if not file then
                        vim.notify(('could not locate %s'):format(item.name),
                            vim.log.levels.WARN, { title = 'CTest' })
                        return
                    end
                    vim.cmd.edit(file)
                    vim.api.nvim_win_set_cursor(0, { line, (col or 1) - 1 })
                end,
            },
            win = {
                input = { keys = { ['<c-]>'] = { 'goto_declaration', mode = { 'n', 'i' } } } },
                list = { keys = { ['<c-]>'] = 'goto_declaration' } },
            },
            confirm = function(picker)
                local selected = picker:selected({ fallback = true })
                picker:close()

                local names = {}
                for _, item in ipairs(selected) do
                    if item.all then
                        return run(nil)
                    end
                    names[#names + 1] = item.name
                end
                run(names)
            end,
        })
    end)
end

return M
