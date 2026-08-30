local cmake = require('qss_nvim.cmake-tools.state')

return {
    name = 'cmake configure',
    params = function()
        local presets = cmake.preset_names('configure')
        if #presets == 0 then
            return {
                build_dir = {
                    desc = 'Directory to configure into',
                    type = 'string',
                    default = cmake.build_dir(),
                },
                build_type = {
                    desc = 'CMAKE_BUILD_TYPE',
                    type = 'enum',
                    choices = { 'Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel' },
                    default = cmake.build_type(),
                },
            }
        end
        return {
            preset = {
                desc = 'Configure preset from CMakePresets.json',
                type = 'enum',
                choices = presets,
                default = cmake.selected_preset('configure') or presets[1],
            },
        }
    end,
    builder = function(params)
        local args = params.preset
            and { '--preset', params.preset }
            or { '-S', '.', '-B', params.build_dir, '-DCMAKE_BUILD_TYPE=' .. params.build_type }

        vim.list_extend(args, cmake.generate_options())

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
