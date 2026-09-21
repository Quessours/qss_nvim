-- Preflight checks for a kas build, in the shape :CMakeDoctor reports them.
--
-- Every failure this reports has been seen as a kas error message that does not
-- say which of its causes applied: "Did not find any init-build-env script" is
-- the same line whether the project was never checked out or whether the config
-- in use is an include fragment. This says which.

local layers = require('qss_nvim.kas.layers')
local project = require('qss_nvim.kas.project')
local recipes = require('qss_nvim.kas.recipes')
local tasks = require('qss_nvim.kas.tasks')

local M = {}

---@class qss.kas.Finding
---@field level "ok"|"warn"|"error"
---@field text string
---@field fix string?

--- Whether any repository under the work directory carries the script kas
--- sources to build the environment. This is the exact condition behind kas's
--- "Did not find any init-build-env script".
---@param root string
---@return string?
local function init_script(root)
    local found = vim.fn.systemlist({
        'find', root, '-maxdepth', '4',
        '(', '-name', 'tmp', '-o', '-name', '.git', ')', '-prune', '-o',
        '(', '-name', 'oe-init-build-env', '-o', '-name', 'isar-init-build-env', ')',
        '-print',
    })
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return found[1]
end

---@return qss.kas.Finding[]
function M.run()
    local findings = {}
    local function add(level, text, fix)
        table.insert(findings, { level = level, text = text, fix = fix })
    end

    local runner = project.runner()
    if not runner then
        add('error', 'neither kas-container nor kas is on PATH', 'install kas')
        return findings
    end
    -- Both runners print their own name in the version line.
    local version = vim.fn.systemlist({ runner, '--version' })[1]
    if not version or version == '' then
        version = runner
    end
    add('ok', version)

    if runner == 'kas-container' then
        local engine = vim.env.KAS_CONTAINER_ENGINE
        if engine and engine ~= '' then
            add('ok', 'container engine: ' .. engine .. ' (from KAS_CONTAINER_ENGINE)')
        elseif vim.fn.executable('docker') == 1 or vim.fn.executable('podman') == 1 then
            add('ok', 'container engine: docker or podman on PATH')
        else
            add('error', 'kas-container needs docker or podman, and neither is on PATH',
                'install one, or set KAS_CONTAINER_ENGINE')
        end
    end

    local root = project.root()
    if not root then
        add('error', 'no kas config above this buffer',
            'open a file inside the project, or cd to it')
        return findings
    end
    add('ok', 'project: ' .. vim.fn.fnamemodify(root, ':~'))

    local configs = project.configs(root)
    if #configs == 0 then
        add('error', 'no kas config in ' .. root, nil)
        return findings
    end
    add('ok', ('%d config file(s): %s'):format(#configs, table.concat(configs, ', ')))

    -- kas resolves the first file of a colon joined list against the rest, so
    -- that is the one that has to stand on its own.
    local selected = project.selected_config(root)
    local base = selected and (selected:match('^[^:]+') or selected)
    if not selected or not base then
        add('error', 'no config selected', ':KasConfig  (<leader>kk)')
    elseif project.is_standalone(root, base) then
        add('ok', ('config in use: %s (%s)'):format(selected, project.config_kind(root, base)))
    else
        add('warn', ('config in use: %s, a fragment that declares no repos'):format(selected),
            'kas fails with "Did not find any init-build-env script" on one of ' ..
            'those: pick another with :KasConfig  (<leader>kk)')
    end

    -- Everything below is about the checkout, which is what a query needs.
    local script = init_script(root)
    if script then
        add('ok', 'init script: ' .. vim.fn.fnamemodify(script, ':~'))
    else
        add('error', 'no oe-init-build-env under the project',
            'the repos are not checked out: :KasCheckout  (<leader>kc)')
    end

    local build = project.build_dir(root)
    if build and vim.fn.isdirectory(build) == 1 then
        add('ok', 'build directory: ' .. vim.fn.fnamemodify(build, ':~'))
    else
        add('warn', 'no build directory yet at ' .. tostring(build),
            ':KasCheckout  (<leader>kc), or set KAS_BUILD_DIR')
    end

    local bblayers = build and (build .. '/conf/bblayers.conf')
    if bblayers and vim.fn.filereadable(bblayers) == 1 then
        add('ok', 'bblayers.conf, so the layer list is the one bitbake parses')
    else
        add('warn', 'no bblayers.conf, so the layers are found by scanning the checkout',
            ':KasCheckout  (<leader>kc) writes it')
    end

    local roots = layers.roots(root)
    if #roots == 0 then
        add('error', 'no layers found', ':KasCheckout  (<leader>kc)')
        return findings
    end
    add('ok', ('%d layers, first is %s'):format(#roots, vim.fn.fnamemodify(roots[1], ':~')))

    local unresolved = layers.unresolved or {}
    if #unresolved > 0 then
        add('warn', 'bblayers.conf names variables this cannot expand: ' ..
            table.concat(unresolved, ', '),
            'the layers above come from scanning the checkout, so the list can ' ..
            'hold layers the build does not parse')
    end

    local found = recipes.list(root)
    if #found == 0 then
        add('warn', 'no recipes in those layers', '<C-r> in the recipe picker rebuilds the index')
    else
        add('ok', ('%d recipes indexed'):format(#found))
    end

    local descriptions = 0
    for _ in pairs(tasks.descriptions(root)) do
        descriptions = descriptions + 1
    end
    if descriptions == 0 then
        add('warn', 'no conf/documentation.conf in any layer, so tasks have no descriptions',
            'the file lives in poky/meta, so the layer list is probably wrong')
    else
        add('ok', ('%d documented tasks'):format(descriptions))
    end

    local bitbake = layers.bitbake_dir(root)
    if bitbake then
        add('ok', 'bitbake: ' .. vim.fn.fnamemodify(bitbake, ':~'))
    else
        add('warn', 'no bitbake directory found beside the layers',
            'the bitbake language server reads its variable docs from there')
    end

    for _, tool in ipairs({ 'language-server-bitbake', 'oelint-adv' }) do
        if vim.fn.executable(tool) == 1 then
            add('ok', tool)
        else
            add('warn', tool .. ' is not installed', ':MasonInstall ' .. tool)
        end
    end

    -- The command a task query runs, so it can be pasted into a shell as it is.
    local argv = project.shell_command('bitbake -c listtasks <recipe>',
        { config = selected, keep_config = true })
    if argv then
        add('ok', 'a task query runs: ' .. table.concat(argv, ' '))
    end

    return findings
end

local MARKERS = { ok = '✓', warn = '!', error = '✗' }
local LEVELS = {
    ok = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
}

---@param findings qss.kas.Finding[]
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

--- Run the checks and show them.
function M.report()
    local findings = M.run()
    local lines = { 'kas doctor' }
    for _, finding in ipairs(findings) do
        lines[#lines + 1] = ('%s %s'):format(MARKERS[finding.level], finding.text)
        if finding.fix then
            lines[#lines + 1] = '    ' .. finding.fix
        end
    end
    vim.notify(table.concat(lines, '\n'), LEVELS[worst(findings)], { title = 'kas' })
end

return M
