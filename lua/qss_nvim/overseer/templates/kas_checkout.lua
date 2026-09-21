local project = require('qss_nvim.kas.project')
local template = require('qss_nvim.kas.template')

return {
    name = 'kas checkout',
    params = function()
        return { config = template.config_param() }
    end,
    builder = function(params)
        return template.definition(project.command('checkout', { config = params.config }),
            { components = { 'default' } })
    end,
}
