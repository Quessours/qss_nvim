local macro = require('qss_nvim.qt-property.macro')
local names = require('qss_nvim.qt-property.names')
local structure = require('qss_nvim.cpp.structure')

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace('qss.qt-property')
local SOURCE = 'Qt property'
local DEBOUNCE = 300

--- The attributes that name a class member, and the wording for each.
local NAMED = {
    { field = 'read', label = 'READ' },
    { field = 'write', label = 'WRITE' },
    { field = 'notify', label = 'NOTIFY' },
    { field = 'reset', label = 'RESET' },
    { field = 'member', label = 'MEMBER' },
}

---@type table<integer, uv.uv_timer_t>
local timers = {}

---@param property qss.qt.Property
---@param message string
---@param lines string[]
---@return vim.Diagnostic
local function diagnostic_for(property, message, lines)
    local text = lines[property.first + 1] or ''
    return {
        lnum = property.first,
        end_lnum = property.last,
        col = #(text:match('^%s*') or ''),
        end_col = #(lines[property.last + 1] or ''),
        severity = vim.diagnostic.severity.WARN,
        source = SOURCE,
        message = message,
    }
end

--- Every gap between what a property promises and what its class declares.
---@param bufnr integer
---@return vim.Diagnostic[]
function M.collect(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local properties, problems = macro.scan(lines)
    local found = {}

    for _, problem in ipairs(problems) do
        found[#found + 1] = {
            lnum = problem.first,
            end_lnum = problem.last,
            col = 0,
            severity = vim.diagnostic.severity.WARN,
            source = SOURCE,
            message = problem.reason,
        }
    end

    for _, property in ipairs(properties) do
        local reason = macro.validate(property)
        if reason and not property.bindable then
            found[#found + 1] = diagnostic_for(property, reason, lines)
        elseif not reason then
            local class = structure.class_at(bufnr, property.first)
            local name = names.of(property)
            if class and name then
                local absent = {}
                for _, attribute in ipairs(NAMED) do
                    local wanted = property[attribute.field]
                    if wanted and not class.declared[wanted] then
                        absent[#absent + 1] = ('%s %s'):format(attribute.label, wanted)
                    end
                end
                if #absent > 0 then
                    found[#found + 1] = diagnostic_for(property,
                        ('%s declares nothing named %s'):format(class.name, table.concat(absent, ', ')),
                        lines)
                end
            end
        end
    end

    return found
end

---@param bufnr integer
local function refresh(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    if vim.g.qss_qt_property_diagnostics == false then
        return vim.diagnostic.reset(NAMESPACE, bufnr)
    end
    vim.diagnostic.set(NAMESPACE, bufnr, M.collect(bufnr))
end

--- Recompute after the buffer settles, so that typing costs one pass rather
--- than one per keystroke.
---@param bufnr integer
local function schedule(bufnr)
    local running = timers[bufnr]
    if running then
        running:stop()
        running:close()
        timers[bufnr] = nil
    end

    local timer = vim.uv.new_timer()
    if not timer then
        return refresh(bufnr)
    end

    timers[bufnr] = timer
    timer:start(DEBOUNCE, 0, function()
        timer:stop()
        timer:close()
        timers[bufnr] = nil
        vim.schedule(function()
            refresh(bufnr)
        end)
    end)
end

--- Turn the check on or off for this session.
function M.toggle()
    local enabled = vim.g.qss_qt_property_diagnostics ~= false
    vim.g.qss_qt_property_diagnostics = not enabled

    if enabled then
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            vim.diagnostic.reset(NAMESPACE, bufnr)
        end
        vim.notify('Qt property diagnostics disabled', vim.log.levels.INFO, { title = SOURCE })
    else
        refresh(vim.api.nvim_get_current_buf())
        vim.notify('Qt property diagnostics enabled', vim.log.levels.INFO, { title = SOURCE })
    end
end

function M.setup()
    local group = vim.api.nvim_create_augroup('QssQtPropertyDiagnostics', { clear = true })

    vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave', 'TextChanged' }, {
        group = group,
        pattern = { '*.h', '*.hpp', '*.hh', '*.hxx', '*.cpp', '*.cc', '*.cxx' },
        desc = 'Check Q_PROPERTY declarations against the class',
        callback = function(event)
            schedule(event.buf)
        end,
    })
end

return M
