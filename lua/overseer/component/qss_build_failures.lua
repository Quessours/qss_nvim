-- Collects the failed steps of a ninja build while it runs. When it fails, the
-- problems they report go to the quickfix list and to a "build problems" task.
-- qss_nvim/overseer/build_failures.lua says what counts as a failed step.

local build_failures = require('qss_nvim.overseer.build_failures')

return {
    desc = 'Collect the failed steps of a ninja build and list their problems',
    params = {
        relative_file_root = {
            desc = 'Where the relative paths in the output start from',
            type = 'string',
            optional = true,
        },
    },
    constructor = function(params)
        local collector = build_failures.collector(params.relative_file_root)
        return {
            ---@type qss.BuildFailure[]
            failures = {},
            on_start = function(self)
                collector = build_failures.collector(params.relative_file_root)
                self.failures = {}
            end,
            on_output_lines = function(_, _, lines)
                for _, line in ipairs(lines) do
                    collector:feed(line)
                end
            end,
            on_complete = function(self, _, status)
                if status ~= 'FAILURE' then
                    return
                end
                self.failures = collector:failures()
                build_failures.to_quickfix(self.failures)
                build_failures.show(self.failures)
            end,
        }
    end,
}
