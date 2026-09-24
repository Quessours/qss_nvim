-- Rendering a list of findings, for the :*Doctor commands.
--
-- A check does not know how its answer will be shown, and every module that
-- runs checks wants the same three things: one notification rather than one per
-- finding, the severity of the whole set taken from the worst of them, and the
-- fix indented under the line it belongs to.

local M = {}

---@class qss.Finding
---@field level "ok"|"warn"|"error"
---@field text string
---@field fix string?

local MARKERS = { ok = '✓', warn = '!', error = '✗' }
local LEVELS = {
    ok = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
}

---@param findings qss.Finding[]
---@return "ok"|"warn"|"error"
function M.worst(findings)
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

--- Everything above `ok`, which is what a command blocks on.
---@param findings qss.Finding[]
---@return qss.Finding[]
function M.blocking(findings)
    return vim.tbl_filter(function(finding)
        return finding.level ~= 'ok'
    end, findings)
end

---@param findings qss.Finding[]
---@param header string
---@param title string the notification title
function M.notify(findings, header, title)
    local lines = { header }
    for _, finding in ipairs(findings) do
        table.insert(lines, ('%s %s'):format(MARKERS[finding.level], finding.text))
        if finding.fix then
            table.insert(lines, '    ' .. finding.fix)
        end
    end
    vim.notify(table.concat(lines, '\n'), LEVELS[M.worst(findings)], { title = title })
end

return M
