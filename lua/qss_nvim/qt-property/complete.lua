local macro = require('qss_nvim.qt-property.macro')
local names = require('qss_nvim.qt-property.names')
local structure = require('qss_nvim.cpp.structure')

local M = {}

local KIND_KEYWORD = 14
local KIND_VARIABLE = 6
local KIND_SNIPPET = 15
local SNIPPET_FORMAT = 2

--- The attributes offered, in the order Qt documents them.
local OFFERED = {
    'READ', 'WRITE', 'MEMBER', 'RESET', 'NOTIFY', 'REVISION',
    'DESIGNABLE', 'SCRIPTABLE', 'STORED', 'USER', 'BINDABLE',
    'CONSTANT', 'FINAL', 'REQUIRED',
}

--- Attributes whose value is a boolean rather than a name.
local BOOLEAN = { DESIGNABLE = true, SCRIPTABLE = true, STORED = true, USER = true }

--- One item, replacing the partial word under the cursor.
---@param cursor qss.qt.Cursor
---@param row integer
---@param col integer
---@param item lsp.CompletionItem
---@param inserted string? what to write, when it differs from the label
---@return lsp.CompletionItem
local function at_word(cursor, row, col, item, inserted)
    item.sortText = item.sortText or '01'
    item.textEdit = {
        range = {
            start = { line = row, character = cursor.word_col },
            ['end'] = { line = row, character = col },
        },
        newText = inserted or item.label,
    }
    return item
end

--- The value each attribute takes, given the names the property implies.
---@param keyword string
---@param name qss.qt.Names
---@return string?
local function value_for(keyword, name)
    local values = {
        READ = name.getter,
        WRITE = name.setter,
        MEMBER = name.member,
        RESET = name.reset,
        NOTIFY = name.signal,
        BINDABLE = 'bindable' .. names.capitalize(name.base),
    }
    return values[keyword]
end

--- Whether an attribute is still worth offering.
---@param keyword string
---@param property qss.qt.Property
---@return boolean
local function available(keyword, property)
    local field = macro.VALUED[keyword] or macro.FLAGS[keyword]
    if field and property[field] then
        return false
    end

    if property.constant and (keyword == 'WRITE' or keyword == 'NOTIFY') then
        return false
    end
    if keyword == 'CONSTANT' and (property.write or property.notify) then
        return false
    end
    return true
end

--- Members of the class that could stand in for the property name.
---@param bufnr integer
---@param row integer
---@return string[]
local function member_names(bufnr, row)
    local class = structure.class_at(bufnr, row)
    if not class then
        return {}
    end

    local found = {}
    for name in pairs(class.declared) do
        if name:match('^m_') then
            found[#found + 1] = name
        end
    end
    table.sort(found)
    return found
end

--- The whole macro, for someone who has typed only its name.
---@param cursor qss.qt.Cursor?
---@param word string
---@param row integer
---@param col integer
---@return lsp.CompletionItem[]
local function skeletons(cursor, word, row, col)
    if cursor or word == '' then
        return {}
    end
    if not ('q_property'):find(word:lower(), 1, true) then
        return {}
    end

    local edit = {
        range = {
            start = { line = row, character = col - #word },
            ['end'] = { line = row, character = col },
        },
    }

    return {
        {
            label = 'Q_PROPERTY(type name)',
            filterText = 'Q_PROPERTY',
            sortText = '01',
            kind = KIND_SNIPPET,
            detail = 'Qt property',
            insertTextFormat = SNIPPET_FORMAT,
            documentation = 'Declare the property, then let the code action add its members.',
            textEdit = vim.tbl_extend('force', edit, {
                newText = 'Q_PROPERTY(${1:QString} ${2:name})$0',
            }),
        },
        {
            label = 'Q_PROPERTY(type name READ WRITE NOTIFY)',
            filterText = 'Q_PROPERTY',
            sortText = '02',
            kind = KIND_SNIPPET,
            detail = 'Qt property',
            insertTextFormat = SNIPPET_FORMAT,
            textEdit = vim.tbl_extend('force', edit, {
                newText = 'Q_PROPERTY(${1:QString} ${2:name} READ ${3:name}'
                    .. ' WRITE ${4:setName} NOTIFY ${5:nameChanged})$0',
            }),
        },
    }
end

--- What to offer at a position.
---@param bufnr integer
---@param position lsp.Position
---@return lsp.CompletionList
function M.at(bufnr, position)
    local row, col = position.line, position.character
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    local word = line:sub(1, col):match('[%w_]*$') or ''

    local cursor = macro.cursor(bufnr, row, col)
    local items = skeletons(cursor, word, row, col)

    if not cursor or cursor.slot == 'type' then
        return { isIncomplete = false, items = items }
    end

    local property = cursor.property
    local name = property and names.of(property) or nil

    if cursor.slot == 'name' then
        for _, member in ipairs(member_names(bufnr, cursor.macro_row)) do
            items[#items + 1] = at_word(cursor, row, col, {
                label = (member:gsub('^m_', '')),
                kind = KIND_VARIABLE,
                detail = ('from %s'):format(member),
            })
        end
        return { isIncomplete = false, items = items }
    end

    if cursor.slot == 'value' then
        local keyword = cursor.keyword or ''
        if BOOLEAN[keyword] then
            for index, literal in ipairs({ 'true', 'false' }) do
                items[#items + 1] = at_word(cursor, row, col, {
                    label = literal,
                    kind = KIND_KEYWORD,
                    sortText = ('0%d'):format(index),
                })
            end
        elseif name then
            local value = value_for(keyword, name)
            if value then
                items[#items + 1] = at_word(cursor, row, col, {
                    label = value,
                    kind = KIND_VARIABLE,
                    detail = ('%s %s'):format(keyword, value),
                })
            end
        end
        return { isIncomplete = false, items = items }
    end

    if not property then
        return { isIncomplete = false, items = items }
    end

    local index = 0
    for _, keyword in ipairs(OFFERED) do
        if available(keyword, property) then
            index = index + 1
            local value = name and value_for(keyword, name) or nil
            local label = keyword
            if value then
                label = ('%s %s'):format(keyword, value)
            end
            items[#items + 1] = at_word(cursor, row, col, {
                label = label,
                filterText = keyword,
                kind = KIND_KEYWORD,
                sortText = ('%02d'):format(index),
                detail = 'Q_PROPERTY',
            })
        end
    end

    return { isIncomplete = false, items = items }
end

return M
