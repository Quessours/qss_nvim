-- How a set of templates says which projects it belongs to.
--
-- An overseer condition matches on the filetype and on a fixed directory, and
-- on nothing else, so a question such as "does this directory hold a
-- CMakeLists.txt" cannot be asked from one. A template provider can ask it: its
-- generator runs once per search, and the search names the directory to answer
-- about.

local overseer = require('overseer')

local M = {}

--- Register templates that are offered only where `applies` accepts the
--- directory the task picker was opened in.
---@param name string the provider name, which overseer reports its errors under
---@param applies fun(dir: string): boolean
---@param modules string[] the modules holding the templates
function M.register(name, applies, modules)
    local templates = vim.tbl_map(require, modules)

    overseer.register_template({
        name = name,
        generator = function(search)
            if not applies(search.dir) then
                return {}
            end
            return templates
        end,
    })
end

return M
