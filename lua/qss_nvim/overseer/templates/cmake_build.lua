local cmake = require('qss_nvim.cmake-tools.state')

--- "all" is what cmake-tools passes when no target is selected.
---@return table
local function target_param()
    local targets = cmake.build_targets()
    if #targets == 0 then
        return {
            desc = 'Target to build, empty for all',
            type = 'string',
            optional = true,
        }
    end

    local choices = { 'all' }
    vim.list_extend(choices, targets)
    return {
        desc = 'Target to build',
        type = 'enum',
        choices = choices,
        default = 'all',
    }
end

return {
    name = 'cmake build',
    params = function()
        local presets = cmake.preset_names('build')
        if #presets == 0 then
            return {
                build_dir = {
                    desc = 'Directory to build',
                    type = 'string',
                    default = cmake.build_dir(),
                },
                target = target_param(),
            }
        end
        return {
            preset = {
                desc = 'Build preset from CMakePresets.json',
                type = 'enum',
                choices = presets,
                default = cmake.selected_preset('build') or presets[1],
            },
            target = target_param(),
        }
    end,
    builder = function(params)
        local args = params.preset
            and { '--build', '--preset', params.preset }
            or { '--build', params.build_dir, '--parallel' }

        if params.target and params.target ~= '' then
            vim.list_extend(args, { '--target', params.target })
        end
        vim.list_extend(args, cmake.build_options())

        return {
            cmd = { 'cmake' },
            args = args,
            components = { 'default' },
        }
    end,
    condition = {
        callback = function(search)
            return cmake.is_cmake_project(search.dir)
        end,
    },
}
