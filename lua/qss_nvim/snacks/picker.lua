-- Picker entry points that need more than a call to a built-in snacks source.
local M = {}

---@param picker snacks.Picker
---@param typed string
local function prefer_exact_path(picker, typed)
    if picker.list.cursor ~= 1 or #picker.list.selected > 0 or not typed:find('/', 1, true) then
        return
    end
    for i = 1, picker.list.topk:count() do
        local item = picker.list:get(i)
        if item and item.file == typed then
            return picker.list:move(i, true)
        end
    end
end

---@param picker snacks.Picker
---@param fn fun(item: snacks.picker.Item?)
local function when_settled(picker, fn)
    local typed = picker.input:get()

    local function run()
        prefer_exact_path(picker, typed)
        fn(picker:current())
    end

    local field = picker.opts.live and 'search' or 'pattern'

    if typed ~= picker.input.filter[field] then
        picker.input.filter[field] = typed
        return picker:find({ on_done = run })
    end
    if picker.matcher:running() then
        return picker.matcher.task:on('done', vim.schedule_wrap(run))
    end
    run()
end

--- bookmarks.nvim ships a telescope extension and nothing else, so this is the
--- snacks equivalent of it: same records, same bookkeeping on jump.
function M.bookmarks()
    Snacks.picker({
        source = 'bookmarks',
        format = 'file',
        finder = function()
            require('bookmarks.list').load_data()

            local items = {}
            for _, bookmark in pairs(require('bookmarks.data').bookmarks) do
                items[#items + 1] = {
                    file = bookmark.filename,
                    pos = { bookmark.line, 0 },
                    -- What the matcher types against: description and path both.
                    text = ('%s %s'):format(bookmark.description, bookmark.filename),
                    label = bookmark.description,
                    bookmark_id = bookmark.id,
                }
            end
            return items
        end,
        confirm = function(picker, _, action)
            when_settled(picker, function(item)
                -- Named after the extension it was written for, but what it does
                -- is bump `fre` and `updated_at`, which is what orders the
                -- bookmark list in bookmarks.nvim's own window.
                if item and item.bookmark_id then
                    require('bookmarks.list').telescope_jump_update(item.bookmark_id)
                end
                Snacks.picker.actions.jump(picker, item, action or {})
            end)
        end,
    })
end

---  lua, rust, cpp, cmake, qml, zig and fish  need no entry.
local ALIASES = {
    qmljs = 'qml',
    bash = 'sh',
    javascriptreact = 'js',
    typescriptreact = 'ts',
}

local rg_types

---@return table<string, boolean>
local function ripgrep_types()
    if not rg_types then
        rg_types = {}
        for _, line in ipairs(vim.fn.systemlist({ 'rg', '--type-list' })) do
            local name = line:match('^([%w%+%-]+):')
            if name then
                rg_types[name] = true
            end
        end
    end
    return rg_types
end

--- Grep restricted to the filetype of the current buffer. A Qt tree layers .cpp,
--- .h, .qml, .pro and CMakeLists over each other, and a word like "visible"
--- appears in all of them; this searches only the layer you are already in.
function M.grep_filetype()
    local filetype = vim.bo.filetype
    local rg_type = ALIASES[filetype] or filetype

    if rg_type == '' or not ripgrep_types()[rg_type] then
        vim.notify(('no ripgrep type for %s; searching everything')
            :format(filetype == '' and 'this buffer' or filetype), vim.log.levels.WARN)
        return Snacks.picker.grep()
    end
    Snacks.picker.grep({ ft = rg_type })
end

---@param picker snacks.Picker
---@param _ snacks.picker.Item?
---@param action snacks.picker.Action
function M.confirm(picker, _, action)
    when_settled(picker, function(item)
        Snacks.picker.actions.confirm(picker, item, action)
    end)
end

return M
