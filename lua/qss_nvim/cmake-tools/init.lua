-- :CMakeBuildChecked and :CMakeDoctor.

local doctor = require('qss_nvim.cmake-tools.doctor')
local state = require('qss_nvim.cmake-tools.state')

local MARKERS = { ok = '✓', warn = '!', error = '✗' }
local LEVELS = {
    ok = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
}

---@param findings qss.cmake.Finding[]
---@return "ok"|"warn"|"error"
local function worst(findings)
    local level = 'ok'
    for _, finding in ipairs(findings) do
        if finding.level == 'error' then
            return 'error'
        elseif finding.level == 'warn' then
            level = 'warn'
        end
    end
    return level
end

---@param findings qss.cmake.Finding[]
---@param header string
local function notify(findings, header)
    local lines = { header }
    for _, finding in ipairs(findings) do
        table.insert(lines, ('%s %s'):format(MARKERS[finding.level], finding.text))
        if finding.fix then
            table.insert(lines, '    ' .. finding.fix)
        end
    end
    vim.notify(table.concat(lines, '\n'), LEVELS[worst(findings)], { title = 'CMake' })
end

---@param clean boolean run cmake's clean target before building
local function build(clean)
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    if not ok then
        return vim.notify('cmake-tools.nvim is not loaded', vim.log.levels.ERROR,
            { title = 'CMake' })
    end
    cmake_tools.build({ bang = clean, fargs = {} })
end

--- Throw the build directory away and configure and build from nothing.
---
--- Distinct from :CMakeBuild!, which runs cmake's `clean` target and therefore
--- keeps CMakeCache.txt -- and a stale cache is usually the reason for wanting
--- this in the first place. cmake-tools' own clean() also returns without
--- calling its callback when there is no cache, so it cannot be chained.
---@param force boolean skip both the setup checks and the confirmation prompt
local function rebuild(force)
    -- Only the setup-stage checks: this is about to create the cache, the
    -- file API reply and compile_commands.json, so reporting them missing would
    -- block the very command that produces them.
    if not force then
        local blocking = vim.tbl_filter(function(finding)
            return finding.stage == 'setup' and finding.level ~= 'ok'
        end, doctor.run())
        if #blocking > 0 then
            return notify(blocking, 'CMake rebuild blocked')
        end
    end

    local ok, cmake_tools = pcall(require, 'cmake-tools')
    if not ok then
        return vim.notify('cmake-tools.nvim is not loaded', vim.log.levels.ERROR,
            { title = 'CMake' })
    end

    local root = vim.fs.normalize(vim.fn.getcwd())
    local dir = (vim.fs.normalize(vim.fn.fnamemodify(state.build_dir(), ':p')):gsub('/$', ''))

    -- An in-source configure leaves a CMakeCache.txt in the project root, so the
    -- cache alone does not make a directory safe to remove.
    if dir == root or dir == '' or dir == '/' then
        return vim.notify(('the build directory resolves to %s; refusing to delete it')
            :format(dir), vim.log.levels.ERROR, { title = 'CMake' })
    end

    local exists = vim.fn.isdirectory(dir) == 1
    if exists and vim.fn.filereadable(dir .. '/CMakeCache.txt') ~= 1 then
        return vim.notify(('%s holds no CMakeCache.txt; refusing to delete it'):format(dir),
            vim.log.levels.ERROR, { title = 'CMake' })
    end

    if exists then
        if not force and vim.fn.confirm(
                ('Delete %s and rebuild from scratch?'):format(dir), '&Yes\n&No', 2) ~= 1 then
            return
        end
        if vim.fn.delete(dir, 'rf') ~= 0 then
            return vim.notify('could not delete ' .. dir, vim.log.levels.ERROR,
                { title = 'CMake' })
        end
    end

    cmake_tools.generate({ bang = false, fargs = {} }, function(result)
        if result:is_ok() then
            cmake_tools.build({ bang = false, fargs = {} })
        end
    end)
end

vim.api.nvim_create_user_command('CMakeRebuild', function(opts)
    rebuild(opts.bang)
end, { bang = true, desc = 'Delete the build directory, then configure and build' })

vim.api.nvim_create_user_command('CMakeDoctor', function()
    notify(doctor.run(), 'CMake setup')
end, { desc = 'Report what CMake setup is missing' })

vim.api.nvim_create_user_command('CMakeBuildChecked', function(opts)
    local argument = opts.fargs[1]
    if argument and argument ~= 'clean' then
        return vim.notify(("expected `clean` or nothing, got `%s`"):format(argument),
            vim.log.levels.ERROR, { title = 'CMake' })
    end
    local clean = argument == 'clean'

    if opts.bang then
        return build(clean)
    end

    local blocking = vim.tbl_filter(function(finding)
        return finding.level ~= 'ok'
    end, doctor.run())

    if #blocking > 0 then
        return notify(blocking, 'CMake build blocked')
    end
    build(clean)
end, {
    bang = true,
    nargs = '?',
    complete = function()
        return { 'clean' }
    end,
    desc = 'Build, after reporting any missing CMake setup',
})
