local overseer = require('overseer')

overseer.register_template(require('qss_nvim.overseer.templates.zig'))
overseer.register_template(require('qss_nvim.overseer.templates.cmake_configure'))
overseer.register_template(require('qss_nvim.overseer.templates.cmake_build'))
overseer.register_template(require('qss_nvim.overseer.templates.cmake_test'))

-- WARN : Don't add things related to rust here. Overseer handles basic cargo commands by default
