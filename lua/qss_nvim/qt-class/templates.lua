---@class qss.qt.Base
---@field label string what the picker shows
---@field name string the class to derive from, empty for a plain class
---@field include string? the Qt header the base class lives in
---@field parent string? what the constructor's parent pointer points at
---@field macro string? the Qt macro the class body opens with
---@field declarations string[]? members declared after the constructor
---@field definitions (fun(name: string): string[])? the matching definitions

local M = {}

--- The pure virtual members of QAbstractListModel, stubbed so that the class
--- compiles as soon as it is written.
---@param name string
---@return string[]
local function model_definitions(name)
    return {
        ('int %s::rowCount(const QModelIndex &parent) const'):format(name),
        '{',
        '    if (parent.isValid()) {',
        '        return 0;',
        '    }',
        '    return 0;',
        '}',
        '',
        ('QVariant %s::data(const QModelIndex &index, int role) const'):format(name),
        '{',
        '    if (!index.isValid()) {',
        '        return {};',
        '    }',
        '    Q_UNUSED(role)',
        '    return {};',
        '}',
    }
end

---@type qss.qt.Base[]
M.bases = {
    {
        label = 'QObject',
        name = 'QObject',
        include = 'QObject',
        parent = 'QObject',
        macro = 'Q_OBJECT',
    },
    {
        label = 'QWidget',
        name = 'QWidget',
        include = 'QWidget',
        parent = 'QWidget',
        macro = 'Q_OBJECT',
    },
    {
        label = 'QDialog',
        name = 'QDialog',
        include = 'QDialog',
        parent = 'QWidget',
        macro = 'Q_OBJECT',
    },
    {
        label = 'QAbstractListModel',
        name = 'QAbstractListModel',
        include = 'QAbstractListModel',
        parent = 'QObject',
        macro = 'Q_OBJECT',
        declarations = {
            'int rowCount(const QModelIndex &parent = QModelIndex()) const override;',
            'QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;',
        },
        definitions = model_definitions,
    },
    {
        label = 'QQuickItem',
        name = 'QQuickItem',
        include = 'QQuickItem',
        parent = 'QQuickItem',
        macro = 'Q_OBJECT',
    },
    {
        label = 'none (plain class)',
        name = '',
    },
}

--- The include guard, derived from the header's own name the way Qt's headers
--- derive theirs.
---@param name string
---@return string
local function guard(name)
    local upper = name:upper():gsub('%W', '_')
    return upper .. '_H'
end

---@param name string
---@param base qss.qt.Base
---@return string
local function constructor_declaration(name, base)
    if not base.parent then
        return ('%s();'):format(name)
    end
    return ('explicit %s(%s *parent = nullptr);'):format(name, base.parent)
end

--- The header, one string per line.
---@param name string
---@param base qss.qt.Base
---@return string[]
function M.header(name, base)
    local macro = guard(name)
    local lines = { '#ifndef ' .. macro, '#define ' .. macro, '' }

    if base.include then
        lines[#lines + 1] = ('#include <%s>'):format(base.include)
        lines[#lines + 1] = ''
    end

    local declaration
    if base.name == '' then
        declaration = ('class %s'):format(name)
    else
        declaration = ('class %s : public %s'):format(name, base.name)
    end

    lines[#lines + 1] = declaration
    lines[#lines + 1] = '{'
    if base.macro then
        lines[#lines + 1] = '    ' .. base.macro
        lines[#lines + 1] = ''
    end
    lines[#lines + 1] = 'public:'
    lines[#lines + 1] = '    ' .. constructor_declaration(name, base)

    if base.declarations then
        lines[#lines + 1] = ''
        for _, member in ipairs(base.declarations) do
            lines[#lines + 1] = '    ' .. member
        end
    end

    lines[#lines + 1] = '};'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '#endif // ' .. macro
    return lines
end

--- The source file, one string per line.
---@param name string
---@param base qss.qt.Base
---@return string[]
function M.source(name, base)
    local lines = { ('#include "%s.h"'):format(name), '' }

    if base.parent then
        lines[#lines + 1] = ('%s::%s(%s *parent)'):format(name, name, base.parent)
        lines[#lines + 1] = ('    : %s(parent)'):format(base.name)
    else
        lines[#lines + 1] = ('%s::%s()'):format(name, name)
    end
    lines[#lines + 1] = '{'
    lines[#lines + 1] = '}'

    if base.definitions then
        lines[#lines + 1] = ''
        for _, line in ipairs(base.definitions(name)) do
            lines[#lines + 1] = line
        end
    end
    return lines
end

return M
