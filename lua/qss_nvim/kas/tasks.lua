-- The tasks of a recipe, and the one-line description of each one.
--
-- Two sources, because the authoritative one is slow. `bitbake -c listtasks`
-- prints exactly the tasks one recipe has, and pays a full metadata parse to do
-- it. The descriptions it prints come from the `[doc]` flags in the layers'
-- conf/documentation.conf, which is a plain file this reads directly. So the
-- documented set answers at once and covers the standard tasks, and the real
-- set for a recipe arrives on request and is then remembered.

local cache = require('qss_nvim.cache').store('qss_kas')
local layers = require('qss_nvim.kas.layers')
local output = require('qss_nvim.kas.output')
local project = require('qss_nvim.kas.project')

local M = {}

local TITLE = 'kas'
local NOTIFICATION = 'qss_kas_tasks'
local DOC_TTL = 24 * 60 * 60
-- The task set of a recipe changes when the layers change, and a week is well
-- inside how long a checkout stands still.
local LIST_TTL = 7 * 24 * 60 * 60

---@class qss.kas.Task
---@field name string
---@field description string

---@param root string
---@return table<string, string>
local function read_descriptions(root)
    local docs = {}
    for _, path in ipairs(layers.files('conf/documentation.conf', root)) do
        local contents = table.concat(vim.fn.readfile(path), '\n'):gsub('\\\n', ' ')
        -- Most of the file quotes with ", a handful of entries with '.
        local patterns = {
            '(do_[%w_%-]+)%[doc%]%s*=%s*"([^"]*)"',
            "(do_[%w_%-]+)%[doc%]%s*=%s*'([^']*)'",
        }
        for _, pattern in ipairs(patterns) do
            for name, description in contents:gmatch(pattern) do
                docs[name] = vim.trim((description:gsub('%s+', ' ')))
            end
        end
    end
    return docs
end

--- Task name to description, for every task the layers document.
---@param root string?
---@param opts { refresh: boolean? }?
---@return table<string, string>
function M.descriptions(root, opts)
    root = root or project.root()
    if not root then
        return {}
    end

    local key = cache.key(root, 'task_docs')
    if (opts or {}).refresh then
        cache.invalidate(key)
    else
        local remembered = cache.get(key)
        if remembered then
            return remembered
        end
    end

    local docs = read_descriptions(root)
    if next(docs) then
        cache.set(key, docs, DOC_TTL)
    end
    return docs
end

--- The documented task set, which is what a recipe nobody has queried yet
--- offers. Every entry carries its description.
---@param root string?
---@return qss.kas.Task[]
function M.documented(root)
    local tasks = {}
    for name, description in pairs(M.descriptions(root)) do
        tasks[#tasks + 1] = { name = name, description = description }
    end
    table.sort(tasks, function(a, b)
        return a.name < b.name
    end)
    return tasks
end

--- do_listtasks pads the name out to the longest one and then writes two
--- spaces, so the description starts at the third space at the earliest. A task
--- with no [doc] flag prints the name alone.
---@param output string
---@return qss.kas.Task[]
function M.parse(output)
    local tasks = {}
    for line in vim.gsplit(output, '\n', { plain = true }) do
        local name, description = line:match('^(do_[%w_%-%.]+)%s%s+(%S.*)$')
        if not name then
            name, description = line:match('^(do_[%w_%-%.]+)%s*$'), ''
        end
        if name then
            tasks[#tasks + 1] = { name = name, description = vim.trim(description) }
        end
    end
    return tasks
end

---@param tasks qss.kas.Task[]
---@param docs table<string, string>
---@return qss.kas.Task[]
local function fill_descriptions(tasks, docs)
    for _, task in ipairs(tasks) do
        if task.description == '' then
            task.description = docs[task.name] or ''
        end
    end
    return tasks
end

---@type table<string, boolean>
local running = {}

--- The tasks of one recipe as bitbake reports them, or nil when nobody has
--- asked yet. `refresh` is what the picker binds to <C-r>.
---@param recipe string
---@param root string?
---@return qss.kas.Task[]?
function M.cached(recipe, root)
    root = root or project.root()
    if not root then
        return nil
    end

    local tasks = cache.get(cache.key(root, 'tasks', recipe))
    if not tasks then
        return nil
    end
    return fill_descriptions(tasks, M.descriptions(root))
end

--- Ask bitbake for the tasks of one recipe. This starts a container and a full
--- metadata parse, so it runs only when something asks for it by name.
---@param recipe string
---@param opts { root: string?, config: string? }?
---@param on_done fun(tasks: qss.kas.Task[]?)
function M.fetch(recipe, opts, on_done)
    opts = opts or {}
    local root = opts.root or project.root()
    if not root then
        return on_done(nil)
    end

    if running[recipe] then
        vim.notify(('already asking bitbake about %s'):format(recipe),
            vim.log.levels.INFO, { title = TITLE })
        return
    end

    local argv = project.shell_command(('bitbake -c listtasks %s'):format(recipe),
        { config = opts.config, keep_config = true })
    if not argv then
        vim.notify('neither kas-container nor kas is installed', vim.log.levels.ERROR,
            { title = TITLE })
        return on_done(nil)
    end

    running[recipe] = true
    if Snacks and Snacks.notifier then
        Snacks.notifier.notify(('parsing the metadata for %s, this takes a while'):format(recipe),
            'info', { id = NOTIFICATION, title = TITLE, timeout = false })
    end

    vim.system(argv, { cwd = root, text = true }, vim.schedule_wrap(function(result)
        running[recipe] = nil
        if Snacks and Snacks.notifier then
            Snacks.notifier.hide(NOTIFICATION)
        end

        local text = ('%s\n%s'):format(result.stdout or '', result.stderr or '')
        local tasks = M.parse(text)
        if #tasks == 0 then
            output.notify_failure(('no tasks for %s'):format(recipe), text, result.code, TITLE)
            return on_done(nil)
        end

        cache.set(cache.key(root, 'tasks', recipe), tasks, LIST_TTL)
        on_done(fill_descriptions(tasks, M.descriptions(root)))
    end))
end

--- What to show for a recipe right now, and where it came from. `source` is
--- "recipe" for the tasks bitbake reported, and "documented" for the generic
--- set that stands in until someone refreshes.
---@param recipe string?
---@param root string?
---@return qss.kas.Task[] tasks, "recipe"|"documented" source
function M.list(recipe, root)
    if recipe then
        local remembered = M.cached(recipe, root)
        if remembered then
            return remembered, 'recipe'
        end
    end
    return M.documented(root), 'documented'
end

--- The names alone, for cmdline completion.
---@param recipe string?
---@param root string?
---@return string[]
function M.names(recipe, root)
    local tasks = M.list(recipe, root)
    return vim.tbl_map(function(task)
        return task.name
    end, tasks)
end

--- Where a task is documented, so that <C-]> in the picker opens something.
---@param name string
---@param root string?
---@return string? path, integer? line
function M.definition(name, root)
    for _, path in ipairs(layers.files('conf/documentation.conf', root)) do
        local lines = vim.fn.readfile(path)
        for number, line in ipairs(lines) do
            if line:find('^' .. vim.pesc(name) .. '%[doc%]') then
                return path, number
            end
        end
    end
    return nil, nil
end

return M
