-- The snacks dashboard has a "Restore Session" key, and it only works when a
-- session plugin sits in the lazy spec: the session section looks the supported
-- ones up by name and runs require('persistence').load() for this one.
return {
    'folke/persistence.nvim',
    event = 'BufReadPre',
    opts = {},
}
