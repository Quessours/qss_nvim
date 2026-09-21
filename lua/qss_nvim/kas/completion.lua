-- Completion inside a recipe.
--
-- The source is registered once and attached per buffer, through
-- cmp.setup.buffer, so it exists only where a bitbake file is open and a C++ or
-- lua buffer keeps exactly the sources it had.
--
-- What it offers depends on where the cursor is, because the three lists are not
-- interchangeable: a task name after `addtask`, a recipe name inside DEPENDS, a
-- class name after `inherit`. Every item carries a one-line detail, which for a
-- task is the description the layers document it with.

local layers = require('qss_nvim.kas.layers')
local project = require('qss_nvim.kas.project')
local recipes = require('qss_nvim.kas.recipes')
local tasks = require('qss_nvim.kas.tasks')

local M = {}

local SOURCE = 'kas'

-- Variables whose value is a list of recipe names.
local DEPENDENCY_VARIABLES = {
    'DEPENDS',
    'RDEPENDS',
    'RRECOMMENDS',
    'RSUGGESTS',
    'PROVIDES',
    'RPROVIDES',
    'PREFERRED_PROVIDER',
    'PREFERRED_RPROVIDER',
}

--- The variable an assignment is for, looking back through the continuation
--- lines: DEPENDS in a recipe is nearly always written over several lines.
---@param buffer integer
---@param row integer 1-based, the line the cursor is on
---@return string?
local function assignment_variable(buffer, row)
    local first = row
    while first > 1 do
        local previous = vim.api.nvim_buf_get_lines(buffer, first - 2, first - 1, false)[1] or ''
        if not previous:match('\\%s*$') then
            break
        end
        first = first - 1
    end

    local line = vim.api.nvim_buf_get_lines(buffer, first - 1, first, false)[1] or ''
    return line:match('^%s*([%w_]+)')
end

---@param variable string?
---@return boolean
local function wants_recipes(variable)
    if not variable then
        return false
    end
    for _, name in ipairs(DEPENDENCY_VARIABLES) do
        if variable == name or variable:find('^' .. name .. '[_:]') then
            return true
        end
    end
    return false
end

---@param kind string
---@return integer
local function completion_kind(kind)
    return require('cmp.types').lsp.CompletionItemKind[kind]
end

---@param buffer integer
---@return table[]
local function task_items(buffer)
    local recipe = recipes.owning(vim.api.nvim_buf_get_name(buffer))
    local found = tasks.list(recipe)

    local items = {}
    for _, task in ipairs(found) do
        items[#items + 1] = {
            label = task.name,
            detail = task.description,
            kind = completion_kind('Function'),
        }
    end
    return items
end

---@return table[]
local function recipe_items()
    local items = {}
    for _, recipe in ipairs(recipes.list()) do
        local detail = vim.fs.basename(recipe.layer)
        if recipe.version then
            detail = ('%s  %s'):format(recipe.version, detail)
        end
        items[#items + 1] = {
            label = recipe.name,
            detail = detail,
            kind = completion_kind('Module'),
        }
    end
    return items
end

---@return table[]
local function class_items()
    local items = {}
    for _, class in ipairs(layers.classes()) do
        items[#items + 1] = {
            label = class.name,
            detail = vim.fs.basename(class.layer),
            kind = completion_kind('Class'),
        }
    end
    return items
end

---@return table[]
local function include_items()
    local items = {}
    for _, recipe in ipairs(recipes.list()) do
        for _, path in ipairs(recipe.includes) do
            items[#items + 1] = {
                label = path:sub(#recipe.layer + 2),
                detail = vim.fs.basename(recipe.layer),
                kind = completion_kind('File'),
            }
        end
    end
    return items
end

---@class qss.kas.CompletionContext
---@field buffer integer
---@field row integer 1-based line the cursor is on
---@field before string the line up to the cursor

--- What the source offers at one cursor position. The three lists are not
--- interchangeable, so the line decides which one is meant.
---@param context qss.kas.CompletionContext
---@return table[]
function M.items(context)
    local before = context.before

    if before:match('^%s*inherit%s') then
        return class_items()
    end
    if before:match('^%s*require%s') or before:match('^%s*include%s') then
        return include_items()
    end
    if before:match('^%s*addtask%s') or before:match('do_[%w_]*$') then
        return task_items(context.buffer)
    end
    if wants_recipes(assignment_variable(context.buffer, context.row)) then
        return recipe_items()
    end
    return {}
end

---@return table
local function source()
    local instance = {}

    function instance.new()
        return setmetatable({}, { __index = instance })
    end

    function instance:is_available()
        return vim.b.qss_kas_completion == true and project.root() ~= nil
    end

    function instance:get_trigger_characters()
        return { '_', '-', '/' }
    end

    function instance:complete(request, callback)
        callback({
            items = M.items({
                buffer = request.context.bufnr,
                row = request.context.cursor.row,
                before = request.context.cursor_before_line,
            }),
            isIncomplete = false,
        })
    end

    return instance
end

local registered = false

--- Turn recipe completion on for one buffer.
---@param buffer integer
function M.attach(buffer)
    local ok, cmp = pcall(require, 'cmp')
    if not ok then
        return
    end

    if not registered then
        cmp.register_source(SOURCE, source().new())
        registered = true
    end

    vim.b[buffer].qss_kas_completion = true
    -- The standard sources stay, in the order the global setup has them. Only
    -- this buffer is affected.
    cmp.setup.buffer({
        sources = cmp.config.sources(
            { { name = SOURCE } },
            { { name = 'nvim_lsp' }, { name = 'path' } },
            { { name = 'buffer', keyword_length = 3 } }
        ),
    })
end

return M
