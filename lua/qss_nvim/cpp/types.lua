local M = {}

--- Types small enough to pass and return by value.
local BY_VALUE = {
    ['bool'] = true,
    ['char'] = true,
    ['signed char'] = true,
    ['unsigned char'] = true,
    ['char8_t'] = true,
    ['char16_t'] = true,
    ['char32_t'] = true,
    ['wchar_t'] = true,
    ['short'] = true,
    ['unsigned short'] = true,
    ['int'] = true,
    ['unsigned'] = true,
    ['unsigned int'] = true,
    ['long'] = true,
    ['unsigned long'] = true,
    ['long long'] = true,
    ['unsigned long long'] = true,
    ['float'] = true,
    ['double'] = true,
    ['long double'] = true,
    ['qreal'] = true,
    ['size_t'] = true,
    ['ptrdiff_t'] = true,
    ['std::size_t'] = true,
    ['qsizetype'] = true,
    ['qintptr'] = true,
    ['quintptr'] = true,
    ['uchar'] = true,
    ['ushort'] = true,
    ['uint'] = true,
    ['ulong'] = true,
}

--- Types worth a member initializer. A class type default-constructs.
local INITIALIZER = { ['bool'] = 'false' }

--- Words that cannot be a parameter name.
local KEYWORDS = {
    ['class'] = true,
    ['const'] = true,
    ['default'] = true,
    ['delete'] = true,
    ['double'] = true,
    ['enum'] = true,
    ['export'] = true,
    ['float'] = true,
    ['int'] = true,
    ['long'] = true,
    ['new'] = true,
    ['operator'] = true,
    ['private'] = true,
    ['public'] = true,
    ['register'] = true,
    ['short'] = true,
    ['signed'] = true,
    ['static'] = true,
    ['switch'] = true,
    ['template'] = true,
    ['this'] = true,
    ['union'] = true,
    ['unsigned'] = true,
    ['using'] = true,
    ['virtual'] = true,
}

---@param word string
---@return boolean
function M.is_keyword(word)
    return KEYWORDS[word] == true
end

--- The type without the qualifiers that do not change how it is passed. A
--- pointer keeps every qualifier: the const in `const char *` belongs to the
--- character, not to the pointer, and dropping it changes the type.
---@param written string
---@return string
local function bare(written)
    local normalized = vim.trim((written:gsub('%s*%*%s*$', ' *')))
    if normalized:match('%*$') then
        return normalized
    end
    local stripped = normalized:gsub('^const%s+', ''):gsub('%s*&+%s*$', '')
    return vim.trim(stripped)
end

M.bare = bare

--- True for a type that goes by value rather than by const reference.
---@param written string
---@return boolean
function M.is_by_value(written)
    local core = bare(written)
    local is_pointer = core:match('%*$') ~= nil
    if is_pointer then
        return true
    end
    if BY_VALUE[core] then
        return true
    end
    local is_qt_enum = core:match('^Qt::') ~= nil or core:match('^QFlags<') ~= nil
    return is_qt_enum
end

--- How a function takes an argument of the type.
---@param written string
---@param name string
---@return string
function M.parameter(written, name)
    local core = bare(written)
    if not M.is_by_value(written) then
        return ('const %s &%s'):format(core, name)
    end
    if core:match('%*$') then
        return ('%s%s'):format(core, name)
    end
    return ('%s %s'):format(core, name)
end

--- How a function hands a value of the type back. Per this config's own
--- decision, a non-trivial type comes back as a const reference to the member.
---@param written string
---@return string
function M.return_type(written)
    local core = bare(written)
    if M.is_by_value(written) then
        return core
    end
    return ('const %s &'):format(core)
end

--- The initializer a member declaration carries, or nil for none.
---@param written string
---@return string?
function M.initializer(written)
    local core = bare(written)
    if core:match('%*$') then
        return 'nullptr'
    end
    if INITIALIZER[core] then
        return INITIALIZER[core]
    end
    if BY_VALUE[core] then
        return '0'
    end
    return nil
end

--- Put a type in front of a name without doubling the space after a pointer
--- or a reference.
---@param written string
---@param rest string
---@return string
function M.join(written, rest)
    if written:match('[%*&]$') then
        return written .. rest
    end
    return ('%s %s'):format(written, rest)
end

return M
