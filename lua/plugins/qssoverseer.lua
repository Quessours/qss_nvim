-- qssoverseer.nvim, the build orchestration on top of overseer.nvim, extracted
-- from this configuration into its own repository. lua/plugins/overseer.lua
-- calls its setup(), and the cmake, cargo and kas code of this configuration
-- requires its modules.
return {
    url = 'git@gitlab.com:Quessours/qssoverseer.nvim.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/qssoverseer.nvim.
    -- dir = '~/dev/qssoverseer.nvim',
    name = 'qssoverseer.nvim',
    lazy = true,
    dependencies = { 'stevearc/overseer.nvim' },
}
