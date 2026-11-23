-- qssoverseer-kas.nvim, the kas and bitbake support extracted from this
-- configuration into its own repository. lua/plugins/overseer.lua calls its
-- setup(). The keys stay in this configuration, in qss_nvim/kas/mappings.lua.
return {
    url = 'git@gitlab.com:Quessours/qssoverseer-kas.nvim.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/qssoverseer-kas.nvim.
    -- dir = '~/dev/qssoverseer-kas.nvim',
    name = 'qssoverseer-kas.nvim',
    -- Not lazy: the plugin's ftplugin/bitbake.lua must be on the runtimepath
    -- for a recipe opened from the command line. The plugin has no plugin/
    -- file, so loading it early runs nothing.
    lazy = false,
    dependencies = {
        'stevearc/overseer.nvim',
        'qssoverseer.nvim',
        'qssoverseer-tools.nvim',
        'folke/snacks.nvim',
    },
}
