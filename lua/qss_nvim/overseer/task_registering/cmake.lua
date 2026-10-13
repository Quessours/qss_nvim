local cmake = require('qss_nvim.cmake-tools.state')
local provider = require('qss_nvim.overseer.provider')

provider.register('cmake', cmake.is_cmake_project, {
    'qss_nvim.overseer.templates.cmake_configure',
    'qss_nvim.overseer.templates.cmake_build',
    'qss_nvim.overseer.templates.cmake_test',
})
