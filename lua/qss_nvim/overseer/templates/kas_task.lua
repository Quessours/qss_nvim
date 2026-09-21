local project = require('qss_nvim.kas.project')
local recipes = require('qss_nvim.kas.recipes')
local run = require('qss_nvim.kas.run')
local tasks = require('qss_nvim.kas.tasks')
local template = require('qss_nvim.kas.template')

-- A project holds thousands of recipes, which is too many for a select list, so
-- the recipe is typed and the task is chosen. <leader>kt is the picker that
-- shows the task descriptions.
return {
    name = 'kas task',
    params = function()
        local recipe = recipes.owning() or ''
        return {
            config = template.config_param(),
            recipe = {
                desc = 'Recipe to run the task on',
                type = 'string',
                default = recipe,
            },
            task = template.choice_param('Task to run', tasks.names(recipe), 'do_compile'),
        }
    end,
    builder = function(params)
        local args = { '--target', params.recipe }
        if params.task and params.task ~= '' then
            vim.list_extend(args, { '-c', run.task_name(params.task) })
        end

        return template.definition(project.command('build', {
            config = params.config,
            args = args,
        }))
    end,
}
