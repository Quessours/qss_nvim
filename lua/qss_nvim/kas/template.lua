-- The pieces every kas overseer template needs: the parameters it offers, and
-- how an argv becomes a task definition.

local project = require('qss_nvim.kas.project')
local run = require('qss_nvim.kas.run')

local M = {}

--- kas takes one config file, or several joined by a colon, which is how a
--- project layers a debug config over a base one. That is free text and not a
--- choice, so the default is the first config in the project.
---@return table
function M.config_param()
    return {
        desc = 'Kas config file, several joined by ":"',
        type = 'string',
        default = project.default_config() or '',
        optional = true,
    }
end

--- An enum parameter, or a free string when nothing is known to offer.
---@param desc string
---@param choices string[]
---@param default string?
---@return table
function M.choice_param(desc, choices, default)
    if #choices == 0 then
        return { desc = desc, type = 'string', optional = true }
    end
    return {
        desc = desc,
        type = 'enum',
        choices = choices,
        default = default or choices[1],
        optional = true,
    }
end

--- The task definition for one kas argv.
---@param argv string[]?
---@param opts { components: (string|table)[]? }?
---@return table
function M.definition(argv, opts)
    if not argv then
        error('neither kas-container nor kas is installed')
    end

    return {
        cmd = { argv[1] },
        args = vim.list_slice(argv, 2),
        cwd = project.root(),
        components = (opts or {}).components or run.components(),
    }
end

return M
