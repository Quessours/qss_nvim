-- The :Kas* commands.
--
-- Same lists as the pickers, reachable from the cmdline with <Tab>, which is
-- faster than a picker once you know the name you want. A command with no
-- argument opens the picker instead of failing.

local picker = require('qss_nvim.kas.picker')
local project = require('qss_nvim.kas.project')
local recipes = require('qss_nvim.kas.recipes')
local run = require('qss_nvim.kas.run')
local targets = require('qss_nvim.kas.targets')
local tasks = require('qss_nvim.kas.tasks')

local M = {}

local TITLE = 'kas'

--- Which argument the cursor is on, counting from one. An empty lead means the
--- cursor sits after a space, so the argument after the last one is meant.
---@param arg_lead string
---@param cmd_line string
---@return integer
local function argument_index(arg_lead, cmd_line)
    local words = vim.split(vim.trim(cmd_line), '%s+')
    local index = #words - 1
    if arg_lead == '' then
        index = index + 1
    end
    return math.max(index, 1)
end

---@param candidates string[]
---@param arg_lead string
---@return string[]
local function matching(candidates, arg_lead)
    if arg_lead == '' then
        return candidates
    end
    return vim.tbl_filter(function(candidate)
        return candidate:find(arg_lead, 1, true) == 1
    end, candidates)
end

---@return boolean
local function in_project()
    if project.root() then
        return true
    end
    vim.notify('no kas config above this buffer', vim.log.levels.WARN, { title = TITLE })
    return false
end

--- The commands, and what completes each argument.
function M.setup()
    vim.api.nvim_create_user_command('KasBuild', function(event)
        if not in_project() then
            return
        end
        if event.args == '' then
            return run.build({})
        end
        run.build({ target = event.fargs[1] })
    end, {
        nargs = '?',
        desc = 'Build a target with kas, or the config targets with no argument',
        complete = function(arg_lead)
            return matching(targets.names(), arg_lead)
        end,
    })

    vim.api.nvim_create_user_command('KasTask', function(event)
        if not in_project() then
            return
        end
        local recipe, task = event.fargs[1], event.fargs[2]
        if not recipe then
            return picker.tasks()
        end
        if not task then
            return picker.tasks(recipe)
        end
        run.build({ target = recipe, task = task })
    end, {
        nargs = '*',
        desc = 'Run one task of one recipe',
        complete = function(arg_lead, cmd_line)
            if argument_index(arg_lead, cmd_line) == 1 then
                return matching(recipes.names(), arg_lead)
            end
            local words = vim.split(vim.trim(cmd_line), '%s+')
            return matching(tasks.names(words[2]), arg_lead)
        end,
    })

    vim.api.nvim_create_user_command('KasRecipe', function(event)
        if not in_project() then
            return
        end
        if event.args == '' then
            return picker.recipes()
        end

        local found = recipes.by_name(event.fargs[1])
        if #found == 0 then
            return vim.notify(('no recipe named %s'):format(event.fargs[1]),
                vim.log.levels.WARN, { title = TITLE })
        end

        local path = recipes.resolve(found[1])
        if not path then
            return vim.notify(('%s is no longer in the layers'):format(event.fargs[1]),
                vim.log.levels.WARN, { title = TITLE })
        end
        vim.cmd.edit(path)
    end, {
        nargs = '?',
        desc = 'Open a recipe',
        complete = function(arg_lead)
            return matching(recipes.names(), arg_lead)
        end,
    })

    vim.api.nvim_create_user_command('KasDevshell', function(event)
        if not in_project() then
            return
        end
        local recipe = event.fargs[1] or recipes.owning()
        if not recipe then
            return vim.notify('name a recipe, or run this from one',
                vim.log.levels.WARN, { title = TITLE })
        end
        run.devshell(recipe)
    end, {
        nargs = '?',
        desc = 'Open a bitbake devshell for a recipe',
        complete = function(arg_lead)
            return matching(recipes.names(), arg_lead)
        end,
    })

    vim.api.nvim_create_user_command('KasConfig', function(event)
        if not in_project() then
            return
        end
        if event.args == '' then
            return picker.configs()
        end

        project.select_config(event.args)
        vim.notify('kas config: ' .. event.args, vim.log.levels.INFO, { title = TITLE })
    end, {
        nargs = '?',
        desc = 'Choose the kas config, or several joined by a colon',
        complete = function(arg_lead)
            return matching(project.configs(), arg_lead)
        end,
    })

    vim.api.nvim_create_user_command('KasShell', function(event)
        if in_project() then
            run.shell(event.args)
        end
    end, { nargs = '+', desc = 'Run one command in the kas build environment' })

    vim.api.nvim_create_user_command('KasCheckout', function()
        if in_project() then
            run.checkout()
        end
    end, { desc = 'Check the project out with kas' })

    vim.api.nvim_create_user_command('KasDump', function()
        if in_project() then
            run.dump()
        end
    end, { desc = 'Print the resolved kas config' })

    vim.api.nvim_create_user_command('KasStatus', function()
        if in_project() then
            run.for_all_repos('git status -sb')
        end
    end, { desc = 'git status in every layer repository' })

    vim.api.nvim_create_user_command('KasClean', function(event)
        if in_project() then
            run.clean(event.fargs[1] or 'clean')
        end
    end, {
        nargs = '?',
        desc = 'Clean the build, the sstate cache or everything',
        complete = function(arg_lead)
            return matching({ 'clean', 'cleansstate', 'cleanall' }, arg_lead)
        end,
    })
end

return M
