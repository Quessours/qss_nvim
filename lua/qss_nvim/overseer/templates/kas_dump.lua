local project = require('qss_nvim.kas.project')
local template = require('qss_nvim.kas.template')

-- The resolved config, after every include and every override. It is the first
-- thing to read when a value is not what the top level config says it is.
return {
    name = 'kas dump',
    params = function()
        return {
            config = template.config_param(),
            format = {
                desc = 'Output format',
                type = 'enum',
                choices = { 'yaml', 'json' },
                default = 'yaml',
            },
            resolve_refs = {
                desc = 'Replace floating refs with exact SHAs',
                type = 'boolean',
                default = false,
            },
        }
    end,
    builder = function(params)
        local args = { '--format', params.format }
        if params.resolve_refs then
            args[#args + 1] = '--resolve-refs'
        end

        return template.definition(project.command('dump', {
            config = params.config,
            args = args,
        }), { components = { 'default' } })
    end,
}
