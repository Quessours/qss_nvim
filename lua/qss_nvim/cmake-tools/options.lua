-- Edit cache variables from a picker, the way ccmake does.
--
-- The variables come from CMakeCache.txt rather than from the option() calls in
-- CMakeLists.txt: options are also declared in subdirectories, in dependencies
-- fetched at configure time, and inside branches that only a configure run
-- resolves, so the text of the tree names some of them at best. The cache also
-- carries the current value, the help string and the advanced flag, which a
-- menu needs anyway.

local state = require('qss_nvim.cmake-tools.state')

local M = {}

--- Types cmake keeps for its own bookkeeping. ccmake hides them, and the
--- per-entry properties below are read out of them.
local HIDDEN_TYPES = { INTERNAL = true, STATIC = true }

--- Everything else, the empty string and NOTFOUND included, is false to cmake.
local TRUE_WORDS = { ON = true, YES = true, TRUE = true, Y = true }

--- Only the words that make a variable a switch. NOTFOUND is false to cmake as
--- well, but a path that was not found is not a switch to offer a checkbox for.
local FALSE_WORDS = { OFF = true, NO = true, FALSE = true, N = true }

---@class qss.cmake.CacheEntry
---@field name string
---@field type string BOOL, STRING, PATH, FILEPATH or UNINITIALIZED
---@field value string as the cache holds it
---@field help string
---@field advanced boolean
---@field choices string[]? the STRINGS property, which cmake-gui offers as a dropdown

--- Values waiting for the next configure run, keyed by entry name, and the build
--- directory they were chosen for. They outlive the picker so that a set of
--- edits costs one configure rather than one configure each.
local pending = {}
local pending_dir = nil

--- ccmake starts with the advanced entries hidden, and so does this.
local show_advanced = false

---@param value string
---@return boolean
local function is_true(value)
    local number = tonumber(value)
    if number then
        return number ~= 0
    end
    return TRUE_WORDS[value:upper()] == true
end

--- cmake stores a variable passed as -DFOO=ON on the command line without a
--- type, so the type alone would leave the most common switch of all as a text
--- prompt.
---@param entry qss.cmake.CacheEntry
---@return boolean
local function is_switch(entry)
    if entry.type == 'BOOL' then
        return true
    end
    if entry.type ~= 'UNINITIALIZED' then
        return false
    end
    local word = entry.value:upper()
    local boolean_word = TRUE_WORDS[word] == true or FALSE_WORDS[word] == true
    return boolean_word or word == '0' or word == '1'
end

---@param value string
---@return string
local function shown(value)
    return value ~= '' and value or '(empty)'
end

--- A run of `//` lines is the help text of the entry right below it, and a line
--- that is neither ends the run.
---@param path string
---@return qss.cmake.CacheEntry[]?
local function read_cache(path)
    local file = io.open(path, 'r')
    if not file then
        return nil
    end

    local entries = {}
    local internal = {}
    local help = {}

    for line in file:lines() do
        local comment = line:match('^//(.*)$')
        if line:sub(1, 1) == '#' then
            -- The header cmake writes documents the syntax as `# KEY:TYPE=VALUE`,
            -- which the entry pattern below otherwise reads as an entry named
            -- "# KEY" holding "VALUE".
            help = {}
        elseif comment then
            help[#help + 1] = vim.trim(comment)
        else
            -- A name holding a space is quoted, and none holds a colon, which is
            -- what separates the name from the type.
            local name, kind, value = line:match('^"?([^:"]+)"?:(%u+)=(.*)$')
            if name and HIDDEN_TYPES[kind] then
                internal[name] = value
            elseif name then
                entries[#entries + 1] = {
                    name = name,
                    type = kind,
                    value = value,
                    help = table.concat(help, ' '),
                }
            end
            help = {}
        end
    end
    file:close()

    for _, entry in ipairs(entries) do
        entry.advanced = internal[entry.name .. '-ADVANCED'] == '1'
        local choices = internal[entry.name .. '-STRINGS']
        entry.choices = choices and vim.split(choices, ';', { trimempty = true }) or nil
    end

    table.sort(entries, function(left, right)
        return left.name < right.name
    end)
    return entries
end

---@param entry qss.cmake.CacheEntry
---@return string
local function current(entry)
    local edited = pending[entry.name]
    if edited then
        return edited
    end
    return entry.value
end

--- A value equal to the one the cache already holds is not a change, so flipping
--- a BOOL twice takes it off the list rather than passing cmake a -D that does
--- nothing.
---@param entry qss.cmake.CacheEntry
---@param value string
local function stage(entry, value)
    pending[entry.name] = value ~= entry.value and value or nil
end

---@param entry qss.cmake.CacheEntry
---@param on_done fun()
local function edit(entry, on_done)
    local value = current(entry)

    if is_switch(entry) then
        stage(entry, is_true(value) and 'OFF' or 'ON')
        return on_done()
    end

    if entry.choices and #entry.choices > 0 then
        return vim.ui.select(entry.choices, { prompt = entry.name }, function(choice)
            if choice then
                stage(entry, choice)
            end
            on_done()
        end)
    end

    vim.ui.input({ prompt = entry.name .. ' = ', default = value }, function(input)
        if input then
            stage(entry, input)
        end
        on_done()
    end)
end

--- A preset only counts if it survived the sentinel filter in state.
---@return string[]
local function configure_args()
    local preset = state.usable_preset('configure')
    if preset then
        return { '--preset', preset }
    end
    return { '-S', '.', '-B', state.build_dir() }
end

local function apply()
    local count = vim.tbl_count(pending)
    if count == 0 then
        return vim.notify('no option was changed', vim.log.levels.WARN, { title = 'CMake' })
    end

    local args = configure_args()
    vim.list_extend(args, state.generate_options())
    -- The last -D for a name wins, so the edits come after the options
    -- cmake-tools passes on every generate.
    for name, value in pairs(pending) do
        args[#args + 1] = ('-D%s=%s'):format(name, value)
    end
    pending = {}

    local overseer = require('overseer')
    local task = overseer.new_task({
        name = ('cmake configure (%d option%s)'):format(count, count == 1 and '' or 's'),
        cmd = { 'cmake' },
        args = args,
        components = { 'default' },
    })
    overseer.open({ enter = false, direction = 'bottom' })
    task:start()
end

--- The column that stands where the checkbox of a BOOL stands, so that the name
--- column starts at the same place on every line.
local TYPE_TAGS = {
    STRING = 'str',
    PATH = 'dir',
    FILEPATH = 'file',
    UNINITIALIZED = '?',
}

--- The help text and the two values, as markdown, for the preview window. An
--- item without one leaves snacks nothing to show but vim.inspect of the item
--- itself.
---@param entry qss.cmake.CacheEntry
---@return string
local function describe(entry)
    local lines = { '# ' .. entry.name, '' }
    if entry.help ~= '' then
        lines[#lines + 1] = entry.help
        lines[#lines + 1] = ''
    end
    lines[#lines + 1] = ('- type: `%s`'):format(entry.type)
    lines[#lines + 1] = ('- in the cache: `%s`'):format(entry.value)

    local staged = pending[entry.name]
    if staged then
        lines[#lines + 1] = ('- staged: `%s`'):format(staged)
    end
    if entry.choices then
        lines[#lines + 1] = ('- choices: %s'):format(table.concat(entry.choices, ', '))
    end
    if entry.advanced then
        lines[#lines + 1] = '- advanced'
    end
    return table.concat(lines, '\n')
end

---@param item table
---@return snacks.picker.Highlight[]
local function format_entry(item)
    local entry = item.entry
    local staged = pending[entry.name]
    local line = { staged and { '● ', 'SnacksPickerGitStatusModified' } or { '  ' } }

    if is_switch(entry) then
        local on = is_true(current(entry))
        line[#line + 1] = on and { '[x]  ', 'SnacksPickerSelected' }
            or { '[ ]  ', 'SnacksPickerUnselected' }
    else
        line[#line + 1] = { Snacks.picker.util.align(TYPE_TAGS[entry.type] or '', 5),
            'SnacksPickerComment' }
    end

    line[#line + 1] = { Snacks.picker.util.align(entry.name, item.width), 'SnacksPickerLabel' }
    line[#line + 1] = { '  ' }

    if staged then
        line[#line + 1] = { shown(entry.value), 'SnacksPickerComment' }
        line[#line + 1] = { ' → ', 'SnacksPickerDelim' }
        line[#line + 1] = { shown(staged), 'SnacksPickerGitStatusModified' }
    elseif entry.value == '' or entry.value:find('NOTFOUND', 1, true) then
        line[#line + 1] = { shown(entry.value), 'SnacksPickerPathIgnored' }
    else
        line[#line + 1] = { entry.value }
    end

    return line
end

---@param entries qss.cmake.CacheEntry[]
---@return table[]
local function items(entries)
    local visible = vim.tbl_filter(function(entry)
        return show_advanced or not entry.advanced
    end, entries)

    local width = 0
    for _, entry in ipairs(visible) do
        width = math.max(width, #entry.name)
    end

    local list = {}
    for _, entry in ipairs(visible) do
        list[#list + 1] = {
            -- What the picker matches against, which is not what it draws: the
            -- help text is only in the preview, and a search for "test" still has
            -- to find the option whose help is the one place the word appears.
            text = ('%s %s %s'):format(entry.name, current(entry), entry.help),
            entry = entry,
            width = width,
            preview = { text = describe(entry), ft = 'markdown' },
        }
    end
    return list
end

--- Pick a cache variable to change. <CR> flips a BOOL and asks for anything
--- else, <c-g> hands the whole set of changes to one configure run.
function M.pick()
    local dir = state.build_dir()
    if pending_dir ~= dir then
        pending, pending_dir = {}, dir
    end

    local entries = read_cache(dir .. '/CMakeCache.txt')
    if not entries then
        return vim.notify(('%s holds no CMakeCache.txt; configure the project once first')
            :format(dir), vim.log.levels.ERROR, { title = 'CMake' })
    end

    Snacks.picker({
        source = 'cmake_options',
        finder = function()
            return items(entries)
        end,
        format = format_entry,
        preview = 'preview',
        title = 'CMake options',
        actions = {
            edit_value = function(picker, item)
                if not (item and item.entry) then
                    return
                end
                edit(item.entry, function()
                    -- Without a target the list jumps back to the first entry,
                    -- which makes flipping several options in a row unusable.
                    picker.list:set_target()
                    picker:refresh()
                end)
            end,
            toggle_advanced = function(picker)
                show_advanced = not show_advanced
                picker.list:set_target()
                picker:refresh()
            end,
            discard = function(picker)
                pending = {}
                picker.list:set_target()
                picker:refresh()
            end,
            apply_changes = function(picker)
                picker:close()
                apply()
            end,
        },
        win = {
            input = {
                keys = {
                    ['<c-g>'] = { 'apply_changes', mode = { 'n', 'i' } },
                    ['<c-x>'] = { 'discard', mode = { 'n', 'i' } },
                    ['<c-a>'] = { 'toggle_advanced', mode = { 'n', 'i' } },
                },
            },
            list = {
                keys = {
                    ['<c-g>'] = 'apply_changes',
                    ['<c-x>'] = 'discard',
                    ['<c-a>'] = 'toggle_advanced',
                },
            },
        },
        confirm = 'edit_value',
        on_close = function()
            local count = vim.tbl_count(pending)
            if count > 0 then
                vim.notify(('%d change%s still waiting for a configure run')
                    :format(count, count == 1 and '' or 's'),
                    vim.log.levels.WARN, { title = 'CMake' })
            end
        end,
    })
end

return M
