-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

local local_files = require("qss_nvim.config.local_files")

require("nvim-tree").setup({
  sort_by = "case_sensitive",
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
    -- Lua patterns matched against the absolute path. An exclusion overrides
    -- every filter, the gitignore one and the dotfile one included, so a
    -- CMakeUserPresets.json or a bitbake local.conf stays visible.
    -- `I` toggles the gitignore filter for everything else, `H` the dotfiles.
    exclude = local_files.tree_patterns(),
    -- vim regexes matched against the name. Forcing a build directory open
    -- above brings its object files with it, because git reports the directory
    -- as ignored and not its contents. This hides them again.
    custom = local_files.tree_custom(),
  },
})
