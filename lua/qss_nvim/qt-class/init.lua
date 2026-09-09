local cmake = require('qss_nvim.qt-class.cmake')
local templates = require('qss_nvim.qt-class.templates')
local utils = require('qss_nvim.utils')
local where = require('qss_nvim.qt-class.where')

local M = {}

local TITLE = 'Qt class'

--- The extensions the argument is allowed to carry, so that `:QtClass Foo.h`
--- means the same as `:QtClass Foo`.
local EXTENSIONS = { '%.h$', '%.hpp$', '%.cpp$', '%.cc$' }

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

--- The class name and, when the argument carries one, the directory it names.
--- A relative directory is taken from the working directory, the way
--- command-line completion offers it. Without one the caller asks.
---@param argument string
---@return string? name, string? dir
local function parse(argument)
    for _, extension in ipairs(EXTENSIONS) do
        argument = argument:gsub(extension, '')
    end

    local parent = vim.fs.dirname(argument)
    local name = vim.fs.basename(argument)

    if not name:match('^[%a_][%w_]*$') then
        notify(('%s is not a valid class name'):format(name), vim.log.levels.ERROR)
        return nil
    end

    if parent == '.' then
        return name, nil
    end

    local absolute = vim.fs.normalize(vim.fn.fnamemodify(parent, ':p'))
    return name, (absolute:gsub('/$', ''))
end

--- Write both files, add them to the build, and open the header.
---@param dir string
---@param name string
---@param base qss.qt.Base
local function write(dir, name, base)
    local header = name .. '.h'
    local source = name .. '.cpp'

    for _, file in ipairs({ header, source }) do
        local path = ('%s/%s'):format(dir, file)
        if vim.uv.fs_stat(path) then
            return notify(('%s already exists'):format(path), vim.log.levels.ERROR)
        end
    end

    if vim.fn.isdirectory(dir) == 0 and vim.fn.mkdir(dir, 'p') == 0 then
        return notify(('could not create %s'):format(dir), vim.log.levels.ERROR)
    end

    local wrote_header = vim.fn.writefile(templates.header(name, base), ('%s/%s'):format(dir, header))
    local wrote_source = vim.fn.writefile(templates.source(name, base), ('%s/%s'):format(dir, source))
    if wrote_header ~= 0 or wrote_source ~= 0 then
        return notify(('could not write the class into %s'):format(dir), vim.log.levels.ERROR)
    end

    local report = cmake.add(dir, header, source)
    local shown = vim.fs.relpath(vim.fn.getcwd(), dir) or dir
    notify(('%s\n  %s and %s in %s\n  %s'):format(name, header, source, shown, report),
        vim.log.levels.INFO)

    local main = utils.main_window()
    if main then
        vim.api.nvim_set_current_win(main)
    end
    vim.cmd.edit(vim.fn.fnameescape(('%s/%s'):format(dir, header)))
end

--- Ask which class to derive from, then write the files.
---@param dir string
---@param name string
local function pick_base(dir, name)
    local items = {}
    for index, base in ipairs(templates.bases) do
        items[#items + 1] = { text = base.label, base = base, idx = index }
    end

    Snacks.picker({
        source = 'qt_class_base',
        items = items,
        format = 'text',
        title = ('Base class of %s'):format(name),
        layout = { preset = 'select' },
        confirm = function(picker, item)
            picker:close()
            if item then
                write(dir, name, item.base)
            end
        end,
    })
end

--- Settle on a directory, then on a base class, then write the class.
---@param argument string a class name, optionally with a directory in front
---@param force boolean take the suggested directory without asking
function M.create(argument, force)
    local name, dir = parse(argument)
    if not name then
        return
    end

    if not Snacks then
        return notify('snacks.nvim is not loaded', vim.log.levels.ERROR)
    end

    if dir then
        return pick_base(dir, name)
    end
    if force then
        return pick_base(where.suggest(), name)
    end

    where.prompt(name, function(chosen)
        pick_base(chosen, name)
    end)
end

vim.api.nvim_create_user_command('QtClass', function(opts)
    local argument = vim.trim(opts.args)
    if argument ~= '' then
        return M.create(argument, opts.bang)
    end
    vim.ui.input({ prompt = 'Class name: ' }, function(answer)
        local given = vim.trim(answer or '')
        if given ~= '' then
            M.create(given, opts.bang)
        end
    end)
end, {
    bang = true,
    nargs = '?',
    complete = 'file',
    desc = 'Create a C++/Qt class (header and source)',
})

return M
