-- :CMakeBuildChecked and :CMakeDoctor.
--
-- Registered from the root init.lua rather than from the plugin spec's config:
-- cmake-tools sits behind a cond gate, and saying so when it did not load is one
-- of the things these commands exist for.
local doctor = require('qss_nvim.cmake-tools.doctor')

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

local function build()
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    if not ok then
        return vim.notify('cmake-tools.nvim is not loaded', vim.log.levels.ERROR,
            { title = 'CMake' })
    end
    -- Our bang means "skip the checks". cmake-tools' own opt.bang means "clean
    -- first", so it is deliberately not forwarded.
    cmake_tools.build({ bang = false, fargs = {} })
end

vim.api.nvim_create_user_command('CMakeDoctor', function()
    notify(doctor.run(), 'CMake setup')
end, { desc = 'Report what CMake setup is missing' })

vim.api.nvim_create_user_command('CMakeBuildChecked', function(opts)
    if opts.bang then
        return build()
    end

    local blocking = vim.tbl_filter(function(finding)
        return finding.level ~= 'ok'
    end, doctor.run())

    if #blocking > 0 then
        return notify(blocking, 'CMake build blocked')
    end
    build()
end, { bang = true, desc = 'Build, after reporting any missing CMake setup' })
