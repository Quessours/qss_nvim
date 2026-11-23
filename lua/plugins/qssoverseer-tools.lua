-- qssoverseer-tools.nvim, the CMake, cargo and device backends extracted from
-- this configuration into their own repository. lua/plugins/overseer.lua calls
-- its setup(). The keys stay in this configuration, in
-- qss_nvim/cmake-tools/mappings.lua and qss_nvim/cargo/mappings.lua.
return {
    url = 'git@gitlab.com:Quessours/qssoverseer-tools.nvim.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/qssoverseer-tools.nvim.
    -- dir = '~/dev/qssoverseer-tools.nvim',
    name = 'qssoverseer-tools.nvim',
    lazy = true,
    dependencies = { 'stevearc/overseer.nvim', 'qssoverseer.nvim', 'folke/snacks.nvim' },
}
