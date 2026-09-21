local project = require('qss_nvim.kas.project')
local template = require('qss_nvim.kas.template')

-- One command in every layer repository the project checked out.
return {
    name = 'kas for-all-repos',
    params = function()
        return {
            config = template.config_param(),
            command = {
                desc = 'Command to run in each repository',
                type = 'string',
                default = 'git status -sb',
            },
        }
    end,
    builder = function(params)
        return template.definition(project.command('for-all-repos', {
            config = params.config,
            args = { params.command },
        }), { components = { 'default' } })
    end,
}
