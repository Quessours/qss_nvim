-- The upstream javiorfo GitHub account no longer exists, so nvim-soil and
-- nvim-nyctophilia come from copies on GitLab. Each copy holds the files of the
-- last upstream commit that this configuration used, without older history.
return {
    url = 'git@gitlab.com:Quessours/nvim-soil.git',
    -- To test local changes, comment out the url line above and uncomment the
    -- dir line below, so that lazy.nvim loads the clone in ~/dev/nvim-soil.
    -- dir = '~/dev/nvim-soil',
    name = 'nvim-soil',

    -- Optional for puml syntax highlighting:
    dependencies = {
        {
            url = 'git@gitlab.com:Quessours/nvim-nyctophilia.git',
            -- dir = '~/dev/nvim-nyctophilia',
            name = 'nvim-nyctophilia',
        },
    },

    lazy = true,
    ft = "plantuml",
    opts = {
        -- If you want to change default configurations

        -- This option closes the image viewer and reopen the image generated
        -- When true this offers some kind of online updating (like plantuml web server)
        actions = {
            redraw = false
        },

        -- If you want to customize the image showed when running this plugin
        image = {
            darkmode = false, -- Enable or disable darkmode
            format = "svg",   -- Choose between png or svg

            -- This is a default implementation of using nsxiv to open the resultant image
            -- Edit the string to use your preferred app to open the image (as if it were a command line)
            -- Some examples:
            -- return "feh " .. img
            -- return "xdg-open " .. img
            execute_to_open = function(img)
                return "feh " .. img
            end
        }
    }
}
