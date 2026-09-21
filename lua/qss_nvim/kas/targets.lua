-- What a build can be pointed at.
--
-- Three sources, cheapest first. The `target` key of the kas config is the
-- answer the project itself gives, and `kas dump` is what resolves it through
-- the includes, so that one is asked for by name only: dump checks the
-- repositories out before it prints. The image recipes of the layers come from
-- the recipe index, which is free. What you built last is remembered here,
-- because it is what you are most likely to build next.

local cache = require('qss_nvim.cache').store('qss_kas')
local output = require('qss_nvim.kas.output')
local project = require('qss_nvim.kas.project')
local recipes = require('qss_nvim.kas.recipes')

local M = {}

local TITLE = 'kas'
local NOTIFICATION = 'qss_kas_dump'
local DUMP_TTL = 24 * 60 * 60
local RECENT_LIMIT = 5

---@class qss.kas.Target
---@field name string
---@field origin string where the name came from, shown next to it

---@param root string
---@return string[]
local function from_dump(root)
    return cache.get(cache.key(root, 'dump_targets')) or {}
end

---@param root string
---@return string[]
local function recent(root)
    return cache.get(cache.key(root, 'recent_targets')) or {}
end

--- Put a target at the front of the remembered list.
---@param name string
---@param root string?
function M.remember(name, root)
    root = root or project.root()
    if not root or name == '' then
        return
    end

    local kept = { name }
    for _, previous in ipairs(recent(root)) do
        if previous ~= name and #kept < RECENT_LIMIT then
            kept[#kept + 1] = previous
        end
    end
    cache.set(cache.key(root, 'recent_targets'), kept)
end

--- Every target worth offering, in the order a picker shows them.
---@param root string?
---@return qss.kas.Target[]
function M.list(root)
    root = root or project.root()
    if not root then
        return {}
    end

    local targets = {}
    local seen = {}

    ---@param name string
    ---@param origin string
    local function add(name, origin)
        if name ~= '' and not seen[name] then
            seen[name] = true
            targets[#targets + 1] = { name = name, origin = origin }
        end
    end

    for _, name in ipairs(recent(root)) do
        add(name, 'built recently')
    end
    for _, name in ipairs(from_dump(root)) do
        add(name, 'kas config target')
    end
    for _, name in ipairs(recipes.image_names(root)) do
        add(name, 'image recipe')
    end
    return targets
end

--- The names alone, for cmdline completion.
---@param root string?
---@return string[]
function M.names(root)
    return vim.tbl_map(function(target)
        return target.name
    end, M.list(root))
end

---@param decoded table
---@return string[]
local function targets_of(decoded)
    local target = decoded.target
    if type(target) == 'string' then
        return { target }
    end
    if type(target) == 'table' then
        return vim.tbl_filter(function(entry)
            return type(entry) == 'string'
        end, target)
    end
    return {}
end

--- Resolve the kas config and remember the targets it declares. This checks the
--- repositories out, so it runs on request and not on the way into a picker.
---@param opts { root: string?, config: string? }?
---@param on_done fun(names: string[]?)
function M.fetch(opts, on_done)
    opts = opts or {}
    local root = opts.root or project.root()
    if not root then
        return on_done(nil)
    end

    local argv = project.command('dump', {
        config = opts.config,
        args = { '--format', 'json' },
    })
    if not argv then
        vim.notify('neither kas-container nor kas is installed', vim.log.levels.ERROR,
            { title = TITLE })
        return on_done(nil)
    end

    if Snacks and Snacks.notifier then
        Snacks.notifier.notify('resolving the kas config', 'info',
            { id = NOTIFICATION, title = TITLE, timeout = false })
    end

    vim.system(argv, { cwd = root, text = true }, vim.schedule_wrap(function(result)
        if Snacks and Snacks.notifier then
            Snacks.notifier.hide(NOTIFICATION)
        end

        local ok, decoded = pcall(vim.json.decode, result.stdout or '')
        if not ok or type(decoded) ~= 'table' then
            local text = ('%s\n%s'):format(result.stdout or '', result.stderr or '')
            output.notify_failure('kas dump failed', text, result.code, TITLE)
            return on_done(nil)
        end

        local names = targets_of(decoded)
        cache.set(cache.key(root, 'dump_targets'), names, DUMP_TTL)
        on_done(names)
    end))
end

return M
