local project = require('qss_nvim.kas.project')
local targets = require('qss_nvim.kas.targets')
local template = require('qss_nvim.kas.template')

-- What `kas build` does with no --target: build the targets the config itself
-- declares. It is the common case, so it is the default, and an enum parameter
-- cannot default to a value that is not one of its choices.
local CONFIG_TARGETS = '(config targets)'

return {
    name = 'kas build',
    params = function()
        local choices = { CONFIG_TARGETS }
        vim.list_extend(choices, targets.names())

        return {
            config = template.config_param(),
            target = template.choice_param('Target to build', choices, CONFIG_TARGETS),
        }
    end,
    builder = function(params)
        local args = {}
        local target = params.target
        if target and target ~= '' and target ~= CONFIG_TARGETS then
            vim.list_extend(args, { '--target', target })
            targets.remember(target)
        end

        return template.definition(project.command('build', {
            config = params.config,
            args = args,
        }))
    end,
}
