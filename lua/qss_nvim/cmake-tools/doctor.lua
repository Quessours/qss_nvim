-- Preflight checks for a CMake build.
--
-- cmake-tools' own build() papers over missing setup: it configures silently when
-- the build directory is absent, and pops a vim.ui.select when a preset or a
-- target is unselected. These checks name what is missing instead, each with the
-- command that fixes it.
local state = require('qss_nvim.cmake-tools.state')

local M = {}

---@class qss.cmake.Finding
---@field level "ok"|"warn"|"error"
---@field text string
---@field fix string?

--- nil when the cond gate in lua/plugins/cmake-tools.lua kept the plugin unloaded.
---@return table?
local function tools()
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    return ok and cmake_tools or nil
end

--- CMakeCache.txt as a KEY -> value table. Entry lines read KEY:TYPE=value; the
--- rest of the file is comments and blanks.
---@param path string
---@return table<string, string>?
local function read_cache(path)
    local fd = io.open(path, 'r')
    if not fd then
        return nil
    end

    local entries = {}
    for line in fd:lines() do
        local key, value = line:match('^([%w_%-%.]+):%u+=(.*)$')
        if key then
            entries[key] = value
        end
    end
    fd:close()
    return entries
end

--- A cache entry cmake filled in with its <VAR>-NOTFOUND sentinel is as good as absent.
---@param value string?
---@return boolean
local function is_set(value)
    return value ~= nil and value ~= '' and not value:match('NOTFOUND$')
end

---@return qss.cmake.Finding[]
function M.run()
    local findings = {}
    local function add(level, text, fix)
        table.insert(findings, { level = level, text = text, fix = fix })
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

    local build_dir = cmake_tools.get_build_directory()
    build_dir = build_dir and vim.fs.normalize(tostring(build_dir))
    if not build_dir then
        add('error', 'cmake-tools has no build directory', ':CMakeGenerate  (<leader>mg)')
        return findings
    end
    -- cmake_build_directory is a template, expanded only once cmake-tools has
    -- configured the project in this session. Before that cmake would take the
    -- "out/${variant:buildType}" spelling literally.
    if build_dir:find('%${') then
        add('error', 'the build directory is still the unexpanded ' .. build_dir,
            ':CMakeGenerate  (<leader>mg)')
        return findings
    end

    local cache = read_cache(build_dir .. '/CMakeCache.txt')
    if not cache then
        add('error', 'not configured: no CMakeCache.txt in ' .. build_dir,
            ':CMakeGenerate  (<leader>mg)')
        return findings
    end
    add('ok', 'configured in ' .. build_dir)

    -- A cache alone is not enough for cmake-tools: build() also wants the file
    -- API reply its own generate() asks for, and quietly reconfigures when it is
    -- missing -- which is what a tree configured by bare `cmake` looks like.
    local codemodel = cmake_tools.get_config():get_codemodel_targets()
    if codemodel.code ~= 0 then
        add('warn', 'no cmake file-API reply; cmake-tools would reconfigure first',
            ':CMakeGenerate  (<leader>mg)')
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

    -- What clangd reads. -DCMAKE_EXPORT_COMPILE_COMMANDS=1 is already forced in
    -- cmake_generate_options, so a missing file means the configure ran elsewhere.
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
