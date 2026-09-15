-- Completion for the slash commands of a Jira edit buffer.
--
-- The source is registered globally but attached per buffer, through
-- cmp.setup.buffer, so `/success` only completes where it means something and
-- never in a Lua file.
local M = {}

local SOURCE = 'jira_slash'

-- What each command writes. The panel types come from the Atlassian editor; the
-- rest are the markdown shapes worth a keystroke.
local COMMANDS = {
    { label = '/info', detail = 'panel', insert = '> [!INFO]\n> ' },
    { label = '/note', detail = 'panel', insert = '> [!NOTE]\n> ' },
    { label = '/tip', detail = 'panel', insert = '> [!TIP]\n> ' },
    { label = '/success', detail = 'panel', insert = '> [!SUCCESS]\n> ' },
    { label = '/warning', detail = 'panel', insert = '> [!WARNING]\n> ' },
    { label = '/error', detail = 'panel', insert = '> [!ERROR]\n> ' },
    { label = '/task', detail = 'task list', insert = '- [ ] ' },
    { label = '/done', detail = 'task list, ticked', insert = '- [x] ' },
    { label = '/code', detail = 'code block', insert = '```\n\n```' },
    { label = '/quote', detail = 'blockquote', insert = '> ' },
    { label = '/rule', detail = 'horizontal rule', insert = '---' },
}

---@return table
local function source()
    local instance = {}

    function instance.new()
        return setmetatable({}, { __index = instance })
    end

    function instance:get_trigger_characters()
        return { '/' }
    end

    -- Only at the start of a line: a slash in the middle of a sentence is a
    -- slash, and a path completes from the path source.
    function instance:is_available()
        return vim.b.qss_jira_slash == true
    end

    function instance:complete(request, callback)
        local before = request.context.cursor_before_line
        if not before:match('^%s*/%a*$') then
            return callback({ items = {}, isIncomplete = false })
        end

        local items = {}
        for _, command in ipairs(COMMANDS) do
            items[#items + 1] = {
                label = command.label,
                detail = command.detail,
                kind = require('cmp.types').lsp.CompletionItemKind.Snippet,
                textEdit = {
                    newText = command.insert,
                    range = {
                        start = { line = request.context.cursor.row - 1, character = 0 },
                        ['end'] = { line = request.context.cursor.row - 1,
                            character = request.context.cursor.col - 1 },
                    },
                },
            }
        end
        callback({ items = items, isIncomplete = false })
    end

    return instance
end

local registered = false

--- Turn the slash commands on for one buffer.
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

    vim.b[buffer].qss_jira_slash = true
    cmp.setup.buffer({
        sources = cmp.config.sources(
            { { name = SOURCE } },
            { { name = 'buffer', keyword_length = 3 }, { name = 'path' } }
        ),
    })
end

--- The commands, for a legend.
---@return string
function M.summary()
    local labels = {}
    for _, command in ipairs(COMMANDS) do
        labels[#labels + 1] = command.label
    end
    return table.concat(labels, ' ')
end

return M
