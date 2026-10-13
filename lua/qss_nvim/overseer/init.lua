local overseer = require('overseer')

overseer.register_template(require('qss_nvim.overseer.templates.zig'))

require('qss_nvim.overseer.task_registering.cmake')
require('qss_nvim.overseer.task_registering.kas')


require('qss_nvim.overseer.log_colors').setup()
require('qss_nvim.overseer.output_jump').setup()
