local M = {}

--- The directory a path stands for.
---@param path string
---@param is_directory boolean
---@return string
local function directory_of(path, is_directory)
    if is_directory then
        return path
    end
    return vim.fs.dirname(path)
end

--- The node nvim-tree's cursor is on, or its root when the cursor is nowhere
--- useful.
---@return string?
local function from_nvim_tree()
    local ok, api = pcall(require, 'nvim-tree.api')
    if not ok or not api.tree.is_visible() then
        return nil
    end

    local node = api.tree.get_node_under_cursor()
    if node and node.absolute_path then
        local target = node.link_to
        if target and vim.fn.isdirectory(target) == 1 then
            return target
        end
        return directory_of(node.absolute_path, node.type == 'directory')
    end

    local explorer = require('nvim-tree.core').get_explorer()
    return explorer and explorer.absolute_path or nil
end

--- The same question asked of the snacks explorer, for the times it is the tree
--- on screen.
---@return string?
local function from_snacks_explorer()
    if not Snacks then
        return nil
    end

    local open = Snacks.picker.get({ source = 'explorer' })
    local explorer = open and open[1]
    if not explorer then
        return nil
    end

    local item = explorer:current()
    if item and item.file then
        return directory_of(item.file, item.dir == true)
    end
    return explorer:cwd()
end

---@return string?
local function from_buffer()
    local name = vim.api.nvim_buf_get_name(0)
    if name == '' then
        return nil
    end
    return vim.fs.dirname(name)
end

--- Every source is wrapped, so that a change in a plugin's own API costs the
--- suggestion rather than the command.
local SOURCES = { from_nvim_tree, from_snacks_explorer, from_buffer }

--- The best guess at where the next class belongs.
---@return string
function M.suggest()
    for _, source in ipairs(SOURCES) do
        local ok, dir = pcall(source)
        if ok and dir and dir ~= '' and vim.fn.isdirectory(dir) == 1 then
            return vim.fs.normalize(dir)
        end
    end
    return vim.fs.normalize(vim.fn.getcwd())
end

--- A path as it is worth showing in a prompt: relative to the working
--- directory, and ending in a separator so that a subdirectory is one word
--- away.
---@param dir string
---@return string
local function shown(dir)
    local relative = vim.fs.relpath(vim.fn.getcwd(), dir) or dir
    return relative .. '/'
end

--- Ask where the class goes, with the suggestion prefilled and Tab completing
--- directory names.
---@param name string the class being created
---@param on_choice fun(dir: string)
function M.prompt(name, on_choice)
    Snacks.input({
        prompt = ('Directory for %s'):format(name),
        default = shown(M.suggest()),
        completion = 'dir',
    }, function(answer)
        local given = vim.trim(answer or '')
        if given == '' then
            return
        end
        local absolute = vim.fs.normalize(vim.fn.fnamemodify(given, ':p'))
        on_choice((absolute:gsub('/$', '')))
    end)
end

return M
