-- Reading a failed kas run.
--
-- kas logs one line per problem, `<timestamp> - ERROR    - <what>`, and then
-- exits non-zero. Reporting the exit code alone hides the one line that says
-- what to do, so both callers of vim.system here pull that line out, and the
-- failures with a known cause get the fix spelled out.

local M = {}

--- The first line kas or bitbake flagged as an error.
---@param output string
---@return string?
function M.first_error(output)
    for line in vim.gsplit(output, '\n', { plain = true }) do
        local trimmed = vim.trim(line)
        if trimmed:find('ERROR') or trimmed:find('error:') then
            -- The timestamp and the level are noise once the line stands alone.
            return (trimmed:gsub('^.- %- ERROR%s*%- ', ''))
        end
    end
    return nil
end

---@class qss.kas.Explanation
---@field cause string
---@field fix string

-- Failures worth naming, because the message alone does not say what to do.
local KNOWN = {
    {
        pattern = 'init%-build%-env',
        cause = 'none of the repositories that config declares holds an ' ..
            'oe-init-build-env script',
        fix = 'the project is not checked out yet, or the config is an include ' ..
            'fragment: run :KasCheckout, or pick a top level config with :KasConfig. ' ..
            ':KasDoctor reports which config was used',
    },
    {
        pattern = 'bblayers%.conf',
        cause = 'the build directory has no bblayers.conf',
        fix = 'run :KasCheckout, which is what writes it',
    },
    {
        pattern = 'Nothing PROVIDES',
        cause = 'bitbake knows no such recipe',
        fix = 'the recipe index comes off the layer files, so a name it offers ' ..
            'can still be excluded from the build; check :KasDoctor for the layers in use',
    },
    {
        pattern = 'Cannot connect to the Docker daemon',
        cause = 'the container engine is not running',
        fix = 'start docker or podman, or set KAS_CONTAINER_ENGINE',
    },
    {
        pattern = 'configuration file .* not found',
        cause = 'kas cannot find the config file it was given',
        fix = 'pick one that exists with :KasConfig',
    },
}

--- What to tell the user about a failure, when the cause is one we know.
---@param output string
---@return qss.kas.Explanation?
function M.explain(output)
    for _, known in ipairs(KNOWN) do
        if output:find(known.pattern) then
            return { cause = known.cause, fix = known.fix }
        end
    end
    return nil
end

--- One notification for a failed run: what kas said, then what to do about it.
---@param subject string what was being attempted
---@param output string stdout and stderr together
---@param code integer
---@param title string
function M.notify_failure(subject, output, code, title)
    local detail = M.first_error(output)
    if not detail then
        detail = ('it exited with %d'):format(code)
    end

    local lines = { ('%s: %s'):format(subject, detail) }
    local explanation = M.explain(output)
    if explanation then
        lines[#lines + 1] = explanation.cause
        lines[#lines + 1] = explanation.fix
    end

    vim.notify(table.concat(lines, '\n'), vim.log.levels.WARN, { title = title })
end

return M
