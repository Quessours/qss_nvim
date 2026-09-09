local M = {}

--- The commands that carry a target's source list, in the order they are
--- preferred: target_sources is the more specific place to add to when a
--- project uses both.
local TARGET_COMMANDS = { { 'target_sources' }, { 'add_executable', 'qt_add_executable', 'add_library' } }

---@class qss.qt.Block
---@field command string the command name, lowercased
---@field argument string the first argument, as written
---@field first integer the line the command opens on
---@field last integer the line its closing parenthesis is on

--- The command a line opens, if it opens one.
---@param line string
---@return string? command, string? argument
local function command_at(line)
    local command, rest = line:match('^%s*([%w_]+)%s*%((.*)$')
    if not command then
        return nil
    end
    return command:lower(), rest:match('^%s*([^%s%)]*)')
end

--- Everything before a trailing comment, so that a parenthesis inside one does
--- not count towards the nesting depth.
---@param line string
---@return string
local function code_of(line)
    return (line:gsub('#.*$', ''))
end

--- Every command in the file, with the line its argument list closes on.
---@param lines string[]
---@return qss.qt.Block[]
local function parse(lines)
    local blocks = {}
    local index = 1

    while index <= #lines do
        local command, argument = command_at(lines[index])
        if not command then
            index = index + 1
        else
            local depth = 0
            local last = index
            for scan = index, #lines do
                local code = code_of(lines[scan])
                depth = depth + select(2, code:gsub('%(', '')) - select(2, code:gsub('%)', ''))
                last = scan
                if depth <= 0 then
                    break
                end
            end
            blocks[#blocks + 1] = {
                command = command,
                argument = argument or '',
                first = index,
                last = last,
            }
            index = last + 1
        end
    end
    return blocks
end

---@param blocks qss.qt.Block[]
---@param command string
---@param argument string
---@return qss.qt.Block?
local function find_set(blocks, command, argument)
    for _, block in ipairs(blocks) do
        if block.command == command and block.argument == argument then
            return block
        end
    end
    return nil
end

--- The one block whose source list the new files belong in, preferring
--- target_sources over the commands that declare the target.
---@param blocks qss.qt.Block[]
---@return qss.qt.Block? block, string? reason
local function find_target(blocks)
    for _, group in ipairs(TARGET_COMMANDS) do
        local matches = {}
        for _, block in ipairs(blocks) do
            if vim.tbl_contains(group, block.command) then
                matches[#matches + 1] = block
            end
        end
        if #matches == 1 then
            return matches[1], nil
        end
        if #matches > 1 then
            return nil, ('%s appears %d times'):format(group[1], #matches)
        end
    end
    return nil, 'no target source list found'
end

--- The indentation the entries of a block already use.
---@param lines string[]
---@param block qss.qt.Block
---@return string
local function entry_indent(lines, block)
    for scan = block.first + 1, block.last do
        local indent, rest = lines[scan]:match('^(%s*)(%S+)')
        if rest and rest ~= ')' then
            return indent
        end
    end
    return lines[block.first]:match('^%s*') .. '    '
end

--- Put `entries` at the end of a block's argument list, in place.
---@param lines string[] modified
---@param block qss.qt.Block
---@param entries string[]
local function insert_entries(lines, block, entries)
    local closing = lines[block.last]
    local before, after = closing:match('^(.*)%)(.*)$')
    if not before then
        return
    end

    if block.first == block.last then
        local head = before:gsub('%s+$', '')
        lines[block.last] = ('%s %s)%s'):format(head, table.concat(entries, ' '), after)
        return
    end

    local indent = entry_indent(lines, block)
    local trailing = vim.trim(before)
    local replacement = {}

    if trailing ~= '' then
        replacement[#replacement + 1] = indent .. trailing
    end
    for _, entry in ipairs(entries) do
        replacement[#replacement + 1] = indent .. entry
    end

    local paren_indent
    if trailing == '' then
        paren_indent = closing:match('^%s*')
    else
        paren_indent = lines[block.first]:match('^%s*')
    end
    replacement[#replacement + 1] = paren_indent .. ')' .. after

    table.remove(lines, block.last)
    for offset, line in ipairs(replacement) do
        table.insert(lines, block.last + offset - 1, line)
    end
end

--- The nearest CMakeLists.txt at or above `dir`, without climbing out of the
--- project.
---@param dir string
---@return string?
local function find_cmakelists(dir)
    local root = vim.fs.root(dir, { '.git', 'CMakePresets.json' }) or vim.fn.getcwd()
    local found = vim.fs.find('CMakeLists.txt', {
        path = dir,
        upward = true,
        type = 'file',
        stop = vim.fs.dirname(vim.fs.normalize(root)),
    })
    return found[1]
end

--- A source list that file(GLOB) fills needs no edit: cmake picks the new files
--- up on its next run.
---@param blocks qss.qt.Block[]
---@return boolean
local function globs_sources(blocks)
    for _, block in ipairs(blocks) do
        local is_glob = block.command == 'file'
            and (block.argument == 'GLOB' or block.argument == 'GLOB_RECURSE')
        if is_glob then
            return true
        end
    end
    return false
end

--- Add the two files to the build.
---@param dir string the directory both files were written to
---@param header string the header's file name
---@param source string the source file's name
---@return string report one line saying what was written, or what was not
function M.add(dir, header, source)
    local path = find_cmakelists(dir)
    if not path then
        return 'no CMakeLists.txt found'
    end

    local shown = vim.fn.fnamemodify(path, ':.')
    local buf = vim.fn.bufnr(path)
    if buf ~= -1 and vim.bo[buf].modified then
        return ('%s has unsaved changes; left alone'):format(shown)
    end

    local lines = vim.fn.readfile(path)
    local blocks = parse(lines)

    if globs_sources(blocks) then
        return ('%s collects sources with file(GLOB); no edit needed'):format(shown)
    end

    local base = vim.fs.dirname(path)
    local prefix = vim.fs.relpath(base, dir) or dir
    local function entry(file)
        if prefix == '.' then
            return file
        end
        return ('%s/%s'):format(prefix, file)
    end

    local headers = find_set(blocks, 'set', 'HEADERS')
    local sources = find_set(blocks, 'set', 'SOURCES')
    local report

    if headers and sources then
        local first, second = headers, sources
        local first_entry, second_entry = entry(header), entry(source)
        if sources.first < headers.first then
            first, second = sources, headers
            first_entry, second_entry = second_entry, first_entry
        end
        insert_entries(lines, second, { second_entry })
        insert_entries(lines, first, { first_entry })
        report = ('added to HEADERS and SOURCES in %s'):format(shown)
    else
        local target, reason = find_target(blocks)
        if not target then
            return ('%s: %s; add the files by hand'):format(shown, reason)
        end
        insert_entries(lines, target, { entry(header), entry(source) })
        report = ('added to %s(%s) in %s'):format(target.command, target.argument, shown)
    end

    if vim.fn.writefile(lines, path) ~= 0 then
        return ('could not write %s'):format(shown)
    end
    vim.cmd.checktime()
    return report
end

return M
