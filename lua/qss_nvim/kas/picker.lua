-- Pickers over the three lists a kas build is driven by: targets, recipes and
-- tasks.
--
-- Each one shows a second, dimmed column, because a name on its own is not
-- enough to choose from: a task without its description is a guess, a recipe
-- without its layer is ambiguous once a bbappend is in play, and a target
-- without its origin does not say whether the project declares it or whether it
-- is simply an image recipe that exists.

local project = require('qss_nvim.kas.project')
local recipes = require('qss_nvim.kas.recipes')
local run = require('qss_nvim.kas.run')
local targets = require('qss_nvim.kas.targets')
local tasks = require('qss_nvim.kas.tasks')

local M = {}

local TITLE = 'kas'

---@param text string
---@param width integer
---@return string
local function align(text, width)
    return Snacks.picker.util.align(text, width, { truncate = true })
end

--- The width of the first column: as wide as the longest name, within reason.
---@param items table[]
---@param field string
---@return integer
local function column_width(items, field)
    local width = 0
    for _, item in ipairs(items) do
        width = math.max(width, #(item[field] or ''))
    end
    return math.min(math.max(width, 12), 44)
end

---@return string?
local function root_or_warn()
    local root = project.root()
    if not root then
        vim.notify('no kas config above this buffer', vim.log.levels.WARN, { title = TITLE })
    end
    return root
end

--- <C-]> and <C-r>, which every picker here binds the same way.
---@param keys table<string, string>
---@return table
local function win_keys(keys)
    local input = {}
    local list = {}
    for key, action in pairs(keys) do
        input[key] = { action, mode = { 'n', 'i' } }
        list[key] = action
    end
    return { input = { keys = input }, list = { keys = list } }
end

---@param path string
---@param line integer?
local function open(path, line)
    local win = require('qss_nvim.utils').main_window()
    if win then
        vim.api.nvim_set_current_win(win)
    end
    vim.cmd.edit(path)
    if line then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
    end
end

--- Open the recipe, or say why not. The index can name a file that an upgrade
--- has since replaced, and :edit on a missing path is what produced an empty
--- buffer, so the path is resolved again first.
---@param recipe qss.kas.Recipe
---@param root string?
local function open_recipe(recipe, root)
    local path, rebuilt = recipes.resolve(recipe, root)
    if not path then
        vim.notify(('%s is no longer in the layers'):format(recipe.name),
            vim.log.levels.WARN, { title = TITLE })
        return
    end

    if rebuilt then
        vim.notify(('%s is now %s; the index was out of date and has been rebuilt')
            :format(recipe.name, vim.fs.basename(path)), vim.log.levels.INFO, { title = TITLE })
    end
    open(path)
end

--- Every file that changes one recipe, in the quickfix list: the recipe itself,
--- then the bbappends and the includes that layer over it.
---@param recipe qss.kas.Recipe
local function set_file_list(recipe)
    local entries = { { filename = recipe.file, lnum = 1, text = 'recipe' } }
    for _, path in ipairs(recipe.appends) do
        entries[#entries + 1] = { filename = path, lnum = 1, text = 'append' }
    end
    for _, path in ipairs(recipe.includes) do
        entries[#entries + 1] = { filename = path, lnum = 1, text = 'include' }
    end

    vim.fn.setqflist({}, ' ', { title = ('kas: %s'):format(recipe.name), items = entries })
    vim.cmd.copen()
end

--- Recipes of every layer in the build.
---@param opts { refresh: boolean?, on_choose: fun(name: string)? }?
function M.recipes(opts)
    opts = opts or {}
    local root = root_or_warn()
    if not root then
        return
    end

    local found = recipes.list(root, { refresh = opts.refresh })
    if #found == 0 then
        return vim.notify('no recipes found; has the project been checked out?',
            vim.log.levels.WARN, { title = TITLE })
    end

    local items = {}
    for index, recipe in ipairs(found) do
        local layer = vim.fs.basename(recipe.layer)
        items[#items + 1] = {
            idx = index,
            name = recipe.name,
            version = recipe.version or '',
            layer = layer,
            file = recipe.file,
            recipe = recipe,
            text = ('%s %s %s'):format(recipe.name, recipe.version or '', layer),
        }
    end

    local names = column_width(items, 'name')
    local versions = column_width(items, 'version')

    Snacks.picker({
        source = 'kas_recipes',
        -- Which tree was searched, because a recipe opened out of a layer makes
        -- that a fair question.
        title = ('kas recipes: %s'):format(vim.fs.basename(root)),
        items = items,
        format = function(item)
            return {
                { align(item.name, names) },
                { ' ' },
                { align(item.version, versions), 'SnacksPickerDimmed' },
                { ' ' },
                { item.layer,                    'SnacksPickerDimmed' },
            }
        end,
        actions = {
            kas_refresh = function(picker)
                picker:close()
                M.recipes({ refresh = true, on_choose = opts.on_choose })
            end,
            kas_tasks = function(picker, item)
                if not item then
                    return
                end
                picker:close()
                M.tasks(item.name)
            end,
            kas_build = function(picker, item)
                if not item then
                    return
                end
                picker:close()
                run.build({ target = item.name })
            end,
            kas_files = function(picker, item)
                if not item then
                    return
                end
                picker:close()
                set_file_list(item.recipe)
            end,
        },
        win = win_keys({
            ['<c-r>'] = 'kas_refresh',
            ['<c-t>'] = 'kas_tasks',
            ['<c-b>'] = 'kas_build',
            ['<c-a>'] = 'kas_files',
        }),
        confirm = function(picker, item)
            if not item then
                return
            end
            picker:close()

            -- Opening the recipe is what you want from a recipe list often
            -- enough that it is the default. <C-b> builds it, <C-t> lists its
            -- tasks, <C-a> collects its appends.
            if opts.on_choose then
                return opts.on_choose(item.name)
            end
            open_recipe(item.recipe, root)
        end,
    })
end

--- Which kas config every command uses. <Tab> selects several, and they are
--- joined with a colon, which is how kas layers one config over another.
function M.configs()
    local root = root_or_warn()
    if not root then
        return
    end

    local names = project.configs(root)
    if #names == 0 then
        return vim.notify('no kas config in ' .. root, vim.log.levels.WARN, { title = TITLE })
    end

    local ORIGINS = {
        repos = 'declares the repos',
        includes = 'includes another config',
        fragment = 'fragment, not buildable on its own',
    }

    local selected = project.selected_config(root) or ''
    local items = {}
    for index, name in ipairs(names) do
        local origin = ORIGINS[project.config_kind(root, name)]
        if name == selected then
            origin = origin .. ', in use'
        end

        items[#items + 1] = {
            idx = index,
            name = name,
            origin = origin,
            file = root .. '/' .. name,
            text = ('%s %s'):format(name, origin),
        }
    end
    local widths = column_width(items, 'name')

    Snacks.picker({
        source = 'kas_configs',
        title = 'kas config',
        items = items,
        format = function(item)
            return {
                { align(item.name, widths) },
                { ' ' },
                { item.origin, 'SnacksPickerDimmed' },
            }
        end,
        confirm = function(picker)
            local chosen = picker:selected({ fallback = true })
            picker:close()

            local wanted = {}
            for _, item in ipairs(chosen) do
                wanted[#wanted + 1] = item.name
            end
            if #wanted == 0 then
                return
            end

            local joined = table.concat(wanted, ':')
            project.select_config(joined, root)
            vim.notify('kas config: ' .. joined, vim.log.levels.INFO, { title = TITLE })
        end,
    })
end

--- What a build can be pointed at.
---@param opts { refresh: boolean? }?
function M.targets(opts)
    opts = opts or {}
    local root = root_or_warn()
    if not root then
        return
    end

    ---@param names string[]?
    local function reopen(names)
        if names then
            M.targets()
        end
    end

    if opts.refresh then
        return targets.fetch({ root = root }, reopen)
    end

    local found = targets.list(root)
    if #found == 0 then
        return vim.notify('no targets known yet; <C-r> resolves the kas config',
            vim.log.levels.WARN, { title = TITLE })
    end

    local items = {}
    for index, target in ipairs(found) do
        items[#items + 1] = {
            idx = index,
            name = target.name,
            origin = target.origin,
            text = ('%s %s'):format(target.name, target.origin),
        }
    end
    local names = column_width(items, 'name')

    Snacks.picker({
        source = 'kas_targets',
        title = ('kas targets: %s'):format(vim.fs.basename(root)),
        items = items,
        -- A target is a name and nothing else. The default previewer reads
        -- item.file and reports "Item has no `file`" for every entry here.
        preview = 'none',
        layout = { hidden = { 'preview' } },
        format = function(item)
            return {
                { align(item.name, names) },
                { ' ' },
                { item.origin, 'SnacksPickerDimmed' },
            }
        end,
        actions = {
            kas_refresh = function(picker)
                picker:close()
                M.targets({ refresh = true })
            end,
            kas_tasks = function(picker, item)
                if not item then
                    return
                end
                picker:close()
                M.tasks(item.name)
            end,
        },
        win = win_keys({
            ['<c-r>'] = 'kas_refresh',
            ['<c-t>'] = 'kas_tasks',
        }),
        confirm = function(picker, item)
            if not item then
                return
            end
            picker:close()
            run.build({ target = item.name })
        end,
    })
end

--- The tasks of one recipe, each with the line the layers document it with.
--- Without a recipe it asks for one first, defaulting to the recipe the current
--- buffer belongs to.
---@param recipe string?
---@param opts { refresh: boolean? }?
function M.tasks(recipe, opts)
    opts = opts or {}
    local root = root_or_warn()
    if not root then
        return
    end

    local subject = recipe or recipes.owning()
    if not subject then
        return M.recipes({
            on_choose = function(name)
                M.tasks(name)
            end,
        })
    end

    if opts.refresh then
        return tasks.fetch(subject, { root = root }, function(found)
            if found then
                M.tasks(subject)
            end
        end)
    end

    local found, source = tasks.list(subject, root)
    if #found == 0 then
        return vim.notify('no task descriptions found in the layers',
            vim.log.levels.WARN, { title = TITLE })
    end

    local items = {}
    for index, task in ipairs(found) do
        items[#items + 1] = {
            idx = index,
            name = task.name,
            description = task.description,
            text = ('%s %s'):format(task.name, task.description),
        }
    end
    local names = column_width(items, 'name')

    local title = ('tasks: %s'):format(subject)
    if source == 'documented' then
        title = title .. ' (documented set, <C-r> asks bitbake)'
    end

    Snacks.picker({
        source = 'kas_tasks',
        title = title,
        items = items,
        -- The description is in the list itself, and a task has no file of its
        -- own, so there is nothing for the file previewer to open. <C-]> is what
        -- opens the line that documents it.
        preview = 'none',
        layout = { hidden = { 'preview' } },
        format = function(item)
            return {
                { align(item.name, names) },
                { ' ' },
                { item.description, 'SnacksPickerDimmed' },
            }
        end,
        actions = {
            kas_refresh = function(picker)
                picker:close()
                M.tasks(subject, { refresh = true })
            end,
            goto_declaration = function(picker, item)
                if not item then
                    return
                end
                picker:close()

                local path, line = tasks.definition(item.name, root)
                if not path then
                    vim.notify(('%s is documented nowhere in the layers'):format(item.name),
                        vim.log.levels.WARN, { title = TITLE })
                    return
                end
                open(path, line)
            end,
            kas_devshell = function(picker)
                picker:close()
                run.devshell(subject)
            end,
        },
        win = win_keys({
            ['<c-r>'] = 'kas_refresh',
            ['<c-]>'] = 'goto_declaration',
            ['<c-s>'] = 'kas_devshell',
        }),
        confirm = function(picker, item)
            if not item then
                return
            end
            picker:close()
            run.build({ target = subject, task = item.name })
        end,
    })
end

return M
