local project = require('qss_nvim.kas.project')
local template = require('qss_nvim.kas.template')

-- clean, cleansstate and cleanall belong to kas-container, and each one throws
-- away more than the last: build artifacts, then the sstate cache, then the
-- downloads.
return {
    name = 'kas clean',
    params = function()
        return {
            what = {
                desc = 'How much to remove',
                type = 'enum',
                choices = { 'clean', 'cleansstate', 'cleanall' },
                default = 'clean',
            },
        }
    end,
    builder = function(params)
        return template.definition(project.command(params.what, { config = '' }),
            { components = { 'default' } })
    end,
}
