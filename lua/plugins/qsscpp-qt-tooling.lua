-- qsscpp-qt-tooling.nvim, the C++ and Qt code generation extracted from this
-- configuration into its own repository. The keys stay in this configuration,
-- in qss_nvim/cpp-impl/mappings.lua, qss_nvim/qt-class/mappings.lua and
-- qss_nvim/qt-property/mappings.lua.
--
-- Not lazy: setup() creates the commands that the keys run, and enables the
-- cppimpl and qtprops language servers, whose lsp/*.lua configurations must
-- be on the runtimepath when the first C++ buffer opens. outline.nvim also
-- finds the QML provider of the plugin on the runtimepath.
return {
    url = 'git@gitlab.com:Quessours/qsscpp-qt-tooling.nvim.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/qsscpp-qt-tooling.nvim.
    -- dir = '~/dev/qsscpp-qt-tooling.nvim',
    name = 'qsscpp-qt-tooling.nvim',
    lazy = false,
    dependencies = { 'folke/snacks.nvim' },
    config = function()
        require('qsscpp_qt_tooling').setup({})
        -- The completion of qtprops wins over the completion of clangd in a
        -- Q_PROPERTY line. The sorting rule belongs to the cmp setup of this
        -- configuration.
        require('qss_nvim.nvim-cmp.client_priority').prefer('qtprops')
    end,
}
