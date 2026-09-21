local overseer = require('overseer')
local cmake = require('qss_nvim.cmake-tools.state')
local kas = require('qss_nvim.kas.project')
local provider = require('qss_nvim.overseer.provider')

overseer.register_template(require('qss_nvim.overseer.templates.zig'))

provider.register('cmake', cmake.is_cmake_project, {
    'qss_nvim.overseer.templates.cmake_configure',
    'qss_nvim.overseer.templates.cmake_build',
    'qss_nvim.overseer.templates.cmake_test',
})

provider.register('kas', function(dir)
    return kas.root(dir) ~= nil
end, {
    'qss_nvim.overseer.templates.kas_build',
    'qss_nvim.overseer.templates.kas_task',
    'qss_nvim.overseer.templates.kas_checkout',
    'qss_nvim.overseer.templates.kas_dump',
    'qss_nvim.overseer.templates.kas_for_all_repos',
})

-- clean, cleansstate and cleanall are kas-container subcommands, and plain kas
-- has none of them.
provider.register('kas clean', function(dir)
    return kas.root(dir) ~= nil and kas.runner() == 'kas-container'
end, {
    'qss_nvim.overseer.templates.kas_clean',
})

require('qss_nvim.overseer.log_colors').setup()

-- WARN : Don't add things related to rust here. Overseer handles basic cargo commands by default
