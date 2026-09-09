local indent = require('qss_nvim.cpp.indent')

local M = {}

--- The order missing sections are created in.
local ORDER = { 'public', 'signals', 'private' }

--- Where each kind of section belongs in a Qt class. A section that must be
--- created goes in front of the first existing section that outranks it, so
--- that public API does not end up below the private members.
local RANK = {
    implicit = 0,
    public = 1,
    protected = 2,
    signals = 3,
    ['public slots'] = 4,
    ['protected slots'] = 5,
    ['private slots'] = 6,
    private = 7,
}

--- Sections that hold slots never receive a plain declaration.
---@param section qss.cpp.Section
---@param kind string
---@return boolean
local function usable(section, kind)
    return section.kind == kind and section.label_row ~= nil
end

--- The last labelled section of a kind, so that hand-written API keeps its
--- place and generated members accumulate below it.
---@param class qss.cpp.ClassInfo
---@param kind string
---@return qss.cpp.Section?
local function target(class, kind)
    local found
    for _, section in ipairs(class.sections) do
        if usable(section, kind) then
            found = section
        end
    end
    return found
end

--- The spelling the header already uses for its signal sections.
---@param code string[]
---@return string
local function signals_label(code)
    for _, line in ipairs(code) do
        if line:match('^%s*Q_SIGNALS%s*:') then
            return 'Q_SIGNALS:'
        end
        if line:match('^%s*signals%s*:') then
            return 'signals:'
        end
    end
    return 'signals:'
end

--- Insertions that put every declaration in its section, creating the sections
--- the class lacks.
---@param bufnr integer
---@param class qss.cpp.ClassInfo
---@param members qss.qt.Member[]
---@param code string[]
---@return qss.cpp.Insertion[]
function M.plan(bufnr, class, members, code)
    local wanted = { public = {}, signals = {}, private = {} }
    for _, member in ipairs(members) do
        local list = wanted[member.section]
        list[#list + 1] = member.declaration
    end

    ---@type qss.cpp.Insertion[]
    local insertions = {}
    local labels = { public = 'public:', signals = signals_label(code), private = 'private:' }
    local label = indent.label(bufnr, class)
    local brace_row = class.body:end_()

    --- The row a new section of this kind goes in front of.
    ---@param kind string
    ---@return integer
    local function anchor_for(kind)
        for _, section in ipairs(class.sections) do
            local outranks = section.label_row ~= nil and (RANK[section.kind] or 0) > RANK[kind]
            if outranks then
                return section.label_row
            end
        end
        return brace_row
    end

    ---@type table<integer, string[]>
    local created = {}
    local anchors = {}

    for _, kind in ipairs(ORDER) do
        local declarations = wanted[kind]
        if #declarations > 0 then
            local section = target(class, kind)
            if section then
                local lines = {}
                local prefix = indent.member(bufnr, class, section)
                for _, declaration in ipairs(declarations) do
                    lines[#lines + 1] = prefix .. declaration
                end
                insertions[#insertions + 1] = { row = section.last + 1, lines = lines }
            else
                local row = anchor_for(kind)
                local block = created[row]
                if not block then
                    block = {}
                    created[row] = block
                    anchors[#anchors + 1] = row
                end

                local prefix = indent.member(bufnr, class, nil)
                if #block > 0 then
                    block[#block + 1] = ''
                end
                block[#block + 1] = label .. labels[kind]
                for _, declaration in ipairs(declarations) do
                    block[#block + 1] = prefix .. declaration
                end
            end
        end
    end

    for _, row in ipairs(anchors) do
        local block = created[row]
        local above = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        if above and vim.trim(above) ~= '' then
            table.insert(block, 1, '')
        end
        if row ~= brace_row then
            block[#block + 1] = ''
        end
        insertions[#insertions + 1] = { row = row, lines = block }
    end

    return insertions
end

return M
