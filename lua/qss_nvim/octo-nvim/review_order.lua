-- In an Octo review, each C++ header comes just before the source file with the
-- same path and name, for example foo.h before foo.cpp. The other files keep
-- the GitHub order, which sorts by path.
--
-- octo.nvim has no option for the file order, so setup() wraps
-- Review:set_files_and_select_first, the method that receives the file list
-- of each review, of each commit of a review and of each change of range.
local M = {}

local HEADER_EXTENSIONS = { h = true, hh = true, hpp = true, hxx = true }
local SOURCE_EXTENSIONS = { c = true, cc = true, cpp = true, cxx = true }

---@param path string
---@return string stem The path without its extension.
---@return string extension
local function split_extension(path)
    local stem, extension = path:match('^(.*)%.([^./]+)$')
    if not stem then
        return path, ''
    end
    return stem, extension
end

---@param files table[] The FileEntry objects of a review, in the GitHub order.
---@return table[] files The same entries, with each header moved before its source file.
local function headers_first(files)
    local header_of_stem = {}
    for _, file in ipairs(files) do
        local stem, extension = split_extension(file.path)
        if HEADER_EXTENSIONS[extension] then
            header_of_stem[stem] = file
        end
    end

    local ordered = {}
    local placed = {}
    for _, file in ipairs(files) do
        local stem, extension = split_extension(file.path)
        local header = SOURCE_EXTENSIONS[extension] and header_of_stem[stem]
        if header and not placed[header] then
            ordered[#ordered + 1] = header
            placed[header] = true
        end
        if not placed[file] then
            ordered[#ordered + 1] = file
            placed[file] = true
        end
    end
    return ordered
end

function M.setup()
    local Review = require('octo.reviews').Review
    local set_files_and_select_first = Review.set_files_and_select_first
    if type(set_files_and_select_first) ~= 'function' then
        vim.notify('octo.nvim has no Review:set_files_and_select_first any more:'
            .. ' the C++ headers of a review keep the GitHub order', vim.log.levels.WARN)
        return
    end
    Review.set_files_and_select_first = function(self, files)
        set_files_and_select_first(self, headers_first(files))
    end
end

return M
