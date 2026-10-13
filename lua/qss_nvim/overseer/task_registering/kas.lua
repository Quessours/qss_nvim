local provider = require('qss_nvim.overseer.provider')
local kas = require('qss_nvim.kas.project')

provider.register('kas', function(dir)
    return kas.root(dir) ~= nil
end, {
    'qss_nvim.overseer.templates.kas_build',
    'qss_nvim.overseer.templates.kas_task',
    'qss_nvim.overseer.templates.kas_checkout',
    'qss_nvim.overseer.templates.kas_dump',
    'qss_nvim.overseer.templates.kas_for_all_repos',
})

provider.register('kas clean', function(dir)
    return kas.root(dir) ~= nil and kas.runner() == 'kas-container'
end, {
    'qss_nvim.overseer.templates.kas_clean',
})
