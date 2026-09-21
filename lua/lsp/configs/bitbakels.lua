-- https://github.com/yoctoproject/vscode-bitbake
--
-- The language server of the Yocto project's own editor extension, installed by
-- mason as `language-server-bitbake`. It reads the recipes and the layer
-- metadata: hover over a variable, jump from a bbappend to the recipe it
-- appends to, complete tasks and variables.
--
-- It runs bitbake itself for the answers it cannot read off the files, and with
-- kas there is no bitbake on the host at all, so `commandWrapper` sends those
-- through the build container instead. The paths it is given are host paths,
-- because the server itself runs here.

---@return string?
local function bitbake_dir()
    local ok, layers = pcall(require, 'qss_nvim.kas.layers')
    if not ok then
        return nil
    end
    return layers.bitbake_dir()
end

---@param root_dir string?
---@return table
local function bitbake_settings(root_dir)
    local ok, project = pcall(require, 'qss_nvim.kas.project')
    if not ok or not root_dir then
        return {}
    end

    local runner = project.runner()
    local settings = {
        pathToBitbakeFolder = bitbake_dir(),
        pathToBuildFolder = project.build_dir(root_dir),
        workingDirectory = root_dir,
    }
    if runner then
        -- The server appends the quoted bitbake command to this string.
        settings.commandWrapper = runner .. ' shell -c'
    end
    return settings
end

---@type vim.lsp.Config
return {
    cmd = { 'language-server-bitbake', '--stdio' },
    filetypes = { 'bitbake' },
    root_dir = function(bufnr, on_dir)
        local ok, project = pcall(require, 'qss_nvim.kas.project')
        local root = ok and project.root(vim.api.nvim_buf_get_name(bufnr)) or nil
        on_dir(root or vim.fs.root(bufnr, { '.git' }))
    end,
    before_init = function(_, config)
        config.settings = vim.tbl_deep_extend('force', config.settings or {}, {
            bitbake = bitbake_settings(config.root_dir),
        })
    end,
}
