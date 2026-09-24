-- Preflight checks for a CMake build.
--
local state = require('qss_nvim.cmake-tools.state')

local M = {}

---@class qss.cmake.Finding
---@field level "ok"|"warn"|"error"
---@field text string
---@field fix string?
---@field stage "setup"|"configured"

--- nil when the cond gate in lua/plugins/cmake-tools.lua kept the plugin unloaded.
---@return table?
local function tools()
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    return ok and cmake_tools or nil
end

--- A cache entry cmake filled in with its <VAR>-NOTFOUND sentinel is as good as absent.
---@param value string?
---@return boolean
local function is_set(value)
    return value ~= nil and value ~= '' and not value:match('NOTFOUND$')
end

--- The file the generator writes last, so its absence says the generate step
--- never ran. CMakeCache.txt cannot say this: cmake writes the cache early and
--- keeps it when the run aborts afterwards.
---@param generator string?
---@return string?
local function generator_file(generator)
    generator = generator or ''
    if generator:find('Ninja') then
        return 'build.ninja'
    elseif generator:find('Makefiles') then
        return 'Makefile'
    end
    return nil
end

--- Why the last configure looks unfinished, or nil when it finished.
---@param build_dir string
---@param cache table<string, string>
---@return string?
local function incomplete_configure(build_dir, cache)
    local file = generator_file(cache.CMAKE_GENERATOR)
    if file and vim.fn.filereadable(build_dir .. '/' .. file) ~= 1 then
        return ('no %s in %s'):format(file, build_dir)
    end

    -- cmake-tools writes the file-API query before configuring, and cmake
    -- answers it only once the run reaches the end.
    local api = build_dir .. '/.cmake/api/v1'
    if vim.fn.isdirectory(api .. '/query') == 1
        and vim.fn.isdirectory(api .. '/reply') ~= 1 then
        return 'cmake left the file-API query unanswered'
    end
    return nil
end

---@class qss.cmake.Missing
---@field name string
---@field file string? the config file cmake looked for, for a config-mode package

--- The packages cmake looked for and did not find. find_package in config mode
--- leaves <Name>_DIR at its NOTFOUND sentinel, which names both the package and
--- the file to search for. The CMAKE_ entries are the platform tools cmake
--- probes for everywhere, so dlltool and tapi are NOTFOUND on every Linux and
--- always will be.
---@param cache table<string, string>
---@return qss.cmake.Missing[]
local function missing_packages(cache)
    local missing = {}
    for key, value in pairs(cache) do
        if value:match('NOTFOUND$') and not key:match('^CMAKE_') then
            local package = key:match('^(.+)_DIR$')
            missing[#missing + 1] = {
                name = package or key,
                file = package and (package .. 'Config.cmake') or nil,
            }
        end
    end
    table.sort(missing, function(left, right)
        return left.name < right.name
    end)
    return missing
end

--- apt-file prints "package: /path/to/file", one line per hit.
---@param file string
---@return string[]
local function apt_file_packages(file)
    local hits = vim.fn.systemlist({ 'apt-file', 'search', file })
    if vim.v.shell_error ~= 0 then
        return {}
    end

    local names, seen = {}, {}
    for _, line in ipairs(hits) do
        local name = line:match('^([^:%s]+):')
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
            if #names == 3 then
                break
            end
        end
    end
    return names
end

--- What to run to get the package. dnf and pacman index the files of packages
--- that are not installed; on Debian only apt-file does, and it is not part of
--- a default install, so saying how to get it is part of the answer.
---@param missing qss.cmake.Missing
---@return string?
local function install_hint(missing)
    if not missing.file then
        return 'install what provides ' .. missing.name
    end

    if vim.fn.executable('apt-file') == 1 then
        local packages = apt_file_packages(missing.file)
        if #packages > 0 then
            return ('sudo apt install %s'):format(table.concat(packages, ' '))
        end
        return ('no packaged file is named %s'):format(missing.file)
    end
    if vim.fn.executable('apt-get') == 1 then
        return ('sudo apt install apt-file && sudo apt-file update, then apt-file search %s')
            :format(missing.file)
    end
    if vim.fn.executable('dnf') == 1 then
        return ("sudo dnf provides '*/%s'"):format(missing.file)
    end
    if vim.fn.executable('pacman') == 1 then
        return ('pacman -F %s'):format(missing.file)
    end
    return ('find what ships %s'):format(missing.file)
end

---@return qss.cmake.Finding[]
function M.run()
    local findings = {}
    local stage = 'setup'
    local function add(level, text, fix)
        table.insert(findings, { level = level, text = text, fix = fix, stage = stage })
    end

    local root = vim.fs.normalize(vim.fn.getcwd())

    if vim.fn.executable('cmake') == 1 then
        add('ok', (vim.fn.systemlist({ 'cmake', '--version' })[1] or 'cmake'))
    else
        add('error', 'cmake is not on PATH', 'install cmake')
    end

    if state.is_cmake_project(root) then
        add('ok', 'CMakeLists.txt in ' .. vim.fn.fnamemodify(root, ':~'))
    else
        add('error', 'no CMakeLists.txt in ' .. vim.fn.fnamemodify(root, ':~'),
            'cd to the project root')
    end

    -- Everything below reads plugin state, so this is where the report stops.
    local cmake_tools = tools()
    if not cmake_tools then
        add('error', 'cmake-tools.nvim is not loaded',
            'its cond gate scans only the directory nvim started in -- ' ..
            ':Lazy load cmake-tools.nvim, or restart from the project root')
        return findings
    end

    local presets_module = require('cmake-tools.presets')
    local preset_files = { presets_module.find_preset_files(root) }
    local has_preset_file = #preset_files > 0
    local presets = nil

    if has_preset_file then
        local names = vim.tbl_map(function(path)
            return vim.fn.fnamemodify(path, ':t')
        end, preset_files)
        add('ok', 'presets: ' .. table.concat(names, ', '))

        -- The failure preset_names() in the overseer template swallows: an
        -- unparseable file there looks exactly like a project with no presets.
        local parsed, result = pcall(presets_module.parse, presets_module, root)
        if parsed then
            presets = result
        else
            add('error', 'the preset file does not parse: ' .. tostring(result),
                'check its JSON, and any file it includes')
        end
    else
        add('ok', 'no preset file; building out of a build directory')
    end

    local configure_preset = cmake_tools.get_configure_preset()
    local build_preset = cmake_tools.get_build_preset()

    if presets then
        if #presets:get_configure_preset_names({}) == 0 then
            add('error', 'the preset file declares no usable configure preset',
                'every configurePresets entry is hidden or disabled')
        elseif not configure_preset then
            add('error', 'no configure preset selected',
                ':CMakeSelectConfigurePreset  (<leader>mp)')
        else
            add('ok', 'configure preset: ' .. configure_preset)
        end

        if #presets:get_build_preset_names({}) == 0 then
            add('warn', 'the preset file declares no build preset',
                'cmake will build the configure preset\'s binaryDir')
        elseif not build_preset then
            add('warn', 'no build preset selected',
                ':CMakeSelectBuildPreset  (<leader>mP)')
        else
            add('ok', 'build preset: ' .. build_preset)
        end

        -- A build preset configured by another configure preset builds a tree
        -- other than the one that was configured, and cmake says nothing.
        if configure_preset and build_preset then
            local selected = presets:get_build_preset(build_preset)
            local owner = selected and selected.configurePreset
            if owner and owner ~= configure_preset then
                add('error',
                    ('build preset %s belongs to configure preset %s, but %s is selected')
                    :format(build_preset, owner, configure_preset),
                    'select presets that name the same tree')
            end
        end
    end

    stage = 'configured'

    local build_dir = cmake_tools.get_build_directory()
    build_dir = build_dir and vim.fs.normalize(tostring(build_dir))
    if not build_dir then
        add('error', 'cmake-tools has no build directory', ':CMakeGenerate  (<leader>mg)')
        return findings
    end
    if build_dir:find('%${') then
        add('error', 'the build directory is still the unexpanded ' .. build_dir,
            ':CMakeGenerate  (<leader>mg)')
        return findings
    end

    local cache = state.cache_values(build_dir .. '/CMakeCache.txt')
    if not cache then
        add('error', 'not configured: no CMakeCache.txt in ' .. build_dir,
            ':CMakeGenerate  (<leader>mg)')
        return findings
    end
    local unfinished = incomplete_configure(build_dir, cache)
    if unfinished then
        local packages = missing_packages(cache)
        -- With a package named below, that name is the fix, and repeating the
        -- command up here would bury it.
        local fix
        if #packages == 0 then
            fix = ':CMakeGenerate  (<leader>mg), and read what it reports'
        end
        add('error', 'the last configure did not finish: ' .. unfinished, fix)

        for _, package in ipairs(packages) do
            add('error', ('cmake did not find the package %s'):format(package.name),
                install_hint(package))
        end
        return findings
    end
    add('ok', 'configured in ' .. build_dir)

    local codemodel = cmake_tools.get_config():get_codemodel_targets()
    if codemodel.code ~= 0 then
        add('warn', 'no cmake file-API reply; cmake-tools would reconfigure first',
            ':CMakeGenerate  (<leader>mg)')
    end

    local configured_type = cache.CMAKE_BUILD_TYPE
    local selected_type = state.build_type()
    local multi_config = vim.tbl_contains(
        { 'Ninja Multi-Config', 'Xcode' }, cache.CMAKE_GENERATOR or '')
        or (cache.CMAKE_GENERATOR or ''):find('Visual Studio') ~= nil
    if not is_set(configured_type) then
        add('ok', multi_config
            and ('build type: chosen per build by ' .. cache.CMAKE_GENERATOR)
            or 'build type: no CMAKE_BUILD_TYPE set, so the binary may carry no debug info')
    elseif configured_type ~= selected_type then
        add('warn', ('configured %s, but %s is selected'):format(configured_type, selected_type),
            ':CMakeGenerate  (<leader>mg)')
    else
        add('ok', 'build type: ' .. configured_type ..
            ((configured_type == 'Debug' or configured_type == 'RelWithDebInfo')
                and '' or ' (not debuggable)'))
    end

    local home = cache.CMAKE_HOME_DIRECTORY
    if home and vim.fs.normalize(home) ~= root then
        add('error', 'the cache was configured for ' .. home,
            'rm -r ' .. build_dir .. ', then :CMakeGenerate  (<leader>mg)')
    end

    local make_program = cache.CMAKE_MAKE_PROGRAM
    if is_set(make_program) then
        if vim.fn.executable(make_program) == 1 then
            add('ok', 'generator: ' .. (cache.CMAKE_GENERATOR or make_program))
        else
            add('error', ('the generator program %s is gone'):format(make_program),
                'install it, or rm -r ' .. build_dir .. ' and :CMakeGenerate')
        end
    end

    for _, key in ipairs({ 'CMAKE_C_COMPILER', 'CMAKE_CXX_COMPILER' }) do
        local compiler = cache[key]
        if is_set(compiler) and vim.fn.executable(compiler) ~= 1 then
            add('error', ('%s is %s, which is gone'):format(key, compiler),
                'rm -r ' .. build_dir .. ', then :CMakeGenerate  (<leader>mg)')
        end
    end

    if vim.fn.filereadable(build_dir .. '/compile_commands.json') == 1 then
        add('ok', 'compile_commands.json')
    else
        add('warn', 'no compile_commands.json in ' .. build_dir .. '; clangd has no flags',
            ':CMakeGenerate  (<leader>mg)')
    end

    -- With presets cmake-tools takes the target from the preset, so it is only
    -- the preset-less path that needs one selected. A preset file that failed to
    -- parse is a preset project too, whatever the parse left behind.
    if not has_preset_file then
        local target = cmake_tools.get_build_target()
        if target then
            add('ok', 'target: ' ..
                (type(target) == 'table' and table.concat(target, ', ') or tostring(target)))
        else
            add('warn', 'no build target selected', ':CMakeSelectBuildTarget  (<leader>mt)')
        end
    end

    return findings
end

return M
