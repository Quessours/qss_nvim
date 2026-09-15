local dap = require('dap')

-- Every bin target of the workspace, as a path under the target directory that
-- `cargo build` writes to.
---@return string[]
local function workspace_binaries()
    local execute = require('qss_nvim.utils').execute_and_capture_output
    local raw = execute('cargo metadata --no-deps --format-version 1 2>/dev/null', true)
    local decoded, metadata = pcall(vim.json.decode, raw)
    if not decoded or type(metadata) ~= 'table' or not metadata.target_directory then
        return {}
    end

    local members = {}
    for _, id in ipairs(metadata.workspace_members or {}) do
        members[id] = true
    end

    local binaries = {}
    for _, package in ipairs(metadata.packages or {}) do
        if members[package.id] then
            for _, target in ipairs(package.targets or {}) do
                if vim.tbl_contains(target.kind or {}, 'bin') then
                    table.insert(binaries, metadata.target_directory .. '/debug/' .. target.name)
                end
            end
        end
    end

    table.sort(binaries)
    return binaries
end

local function default_executable()
    local binaries = workspace_binaries()

    if #binaries == 0 then
        vim.notify('cargo metadata reports no bin target here', vim.log.levels.ERROR)
        return dap.ABORT
    end

    if #binaries == 1 then
        return binaries[1]
    end

    -- nvim-dap resumes a suspended coroutine returned by a configuration value
    return coroutine.create(function(dap_co)
        vim.ui.select(binaries, { prompt = 'Executable to debug' }, function(choice)
            coroutine.resume(dap_co, choice or dap.ABORT)
        end)
    end)
end

dap.configurations.rust = {
    {
        name = "Launch default executable",
        type = "codelldb",
        preLaunchTask = "cargo build",
        request = "launch",
        program = default_executable,
        cwd = "${workspaceFolder}",
        env = { RUST_BACKTRACE = "1" },
        stopOnEntry = false,
        showDisassembly = "never",
        console = 'integratedTerminal',
        sourceLanguages = { 'rust' }
    },
    {
        name = "Launch default executable with custom args",
        type = "codelldb",
        preLaunchTask = "cargo build",
        request = "launch",
        program = default_executable,
        args = function()
            local arguments = vim.fn.input('Arguments: ')
            local split_arguments = {}
            for arg in string.gmatch(arguments, "%a+") do
                table.insert(split_arguments, arg)
            end

            return split_arguments
        end,
        cwd = "${workspaceFolder}",
        env = { RUST_BACKTRACE = "1" },
        stopOnEntry = false,
        showDisassembly = "never",
        console = 'integratedTerminal',
        sourceLanguages = { "rust" }
    },
    {
        name = "Launch an executable",
        type = "codelldb",
        preLaunchTask = "cargo build",
        request = "launch",
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = "${workspaceFolder}",
        env = { RUST_BACKTRACE = "1" },
        stopOnEntry = false,
        showDisassembly = "never",
        console = 'integratedTerminal',
        sourceLanguages = { "rust" }
    },
}


require("qss_nvim.nvim-dap.default_mappings")
