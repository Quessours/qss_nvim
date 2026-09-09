local types = require('qss_nvim.cpp.types')

local M = {}

--- The return type as the source file must read it. A leading return type is
--- looked up before the class scope is entered, so the class name and the
--- types the class declares both take the class qualification with them:
--- `Mode mode() const` defines `Model::Mode Model::mode() const`. No other
--- position needs this. The parameter list and a trailing return type are
--- already read in the class scope.
---@param written string
---@param declaration qss.cpp.Declaration
---@param scope string the qualification the definition writes
---@return string
local function qualify(written, declaration, scope)
    if written == '' or scope == '' or not declaration.in_class then
        return written
    end

    return (written:gsub('()(%f[%w_][%a_][%w_]*)', function(at, word)
        local scoped = written:sub(at - 2, at - 1) == '::'
        if scoped then
            return nil
        end
        if word == declaration.owner then
            return scope
        end
        if declaration.types[word] then
            return ('%s::%s'):format(scope, word)
        end
        return nil
    end))
end

--- The definition of one declaration, and the row of its body.
---@param declaration qss.cpp.Declaration
---@param scope string the qualification to write, empty for none
---@param body_indent string
---@return string[] lines, integer body 0-based row of the body inside the lines
function M.definition(declaration, scope, body_indent)
    local name = declaration.name
    if scope ~= '' then
        name = ('%s::%s'):format(scope, name)
    end

    local signature = ('%s(%s)'):format(name, declaration.parameters)
    if declaration.suffix ~= '' then
        signature = ('%s %s'):format(signature, declaration.suffix)
    end

    local prefix = qualify(declaration.prefix, declaration, scope)

    local head = signature
    if prefix ~= '' then
        head = types.join(prefix, signature)
    end

    return { head, '{', body_indent, '}' }, 2
end

return M
