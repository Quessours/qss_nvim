local cmake = require('qss_nvim.cmake-tools.state')
local tests = require('qss_nvim.cmake-tools.tests')

--- ctest runs one test at a time unless told otherwise, unlike the build, where
--- Ninja parallelises on its own.
---@return integer
local function cpu_count()
    local ok, info = pcall(vim.uv.cpu_info)
    return (ok and info and #info > 0) and #info or 1
end

return {
    name = 'cmake test',
    params = function()
        local presets = cmake.preset_names('test')
        if #presets == 0 then
            return {
                build_dir = {
                    desc = 'Directory holding the test set',
                    type = 'string',
                    default = cmake.build_dir(),
                },
                filter = {
                    desc = 'Only tests matching this regex, empty for all',
                    type = 'string',
                    optional = true,
                },
                jobs = {
                    desc = 'Tests to run at once',
                    type = 'number',
                    default = cpu_count(),
                },
            }
        end

        local selected = cmake.selected_preset('test') or presets[1]
        return {
            preset = {
                desc = 'Test preset from CMakePresets.json',
                type = 'enum',
                choices = presets,
                default = selected,
            },
            filter = {
                desc = 'Only tests matching this regex, empty for all',
                type = 'string',
                optional = true,
            },
            jobs = {
                desc = 'Tests to run at once',
                type = 'number',
                -- A preset that states its own execution.jobs has an opinion
                -- about contention; start from that rather than the core count.
                default = cmake.test_jobs(selected) or cpu_count(),
            },
        }
    end,
    builder = function(params)
        local args = params.preset
            and { '--preset', params.preset }
            or { '--test-dir', params.build_dir, '-C', cmake.build_type() }

        if params.filter and params.filter ~= '' then
            vim.list_extend(args, { '-R', params.filter })
        end
        vim.list_extend(args, { '--output-on-failure' })

        if params.jobs and params.jobs > 1 then
            vim.list_extend(args, { '--parallel', tostring(math.floor(params.jobs)) })
        end

        return {
            cmd = { 'ctest' },
            args = args,
            components = tests.components,
        }
    end,
    condition = {
        callback = function(search)
            return cmake.is_cmake_project(search.dir)
        end,
    },
}
