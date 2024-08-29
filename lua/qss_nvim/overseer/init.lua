local os = require('overseer')

os.register_template(require('qss_nvim.overseer.templates.zig'))
os.register_template(require('qss_nvim.overseer.templates.rust_run_tests'))
