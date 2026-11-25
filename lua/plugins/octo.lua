-- octo.nvim, the GitHub issues, pull requests and reviews in buffers. The
-- plugin talks to GitHub through the gh CLI, so `gh auth login` must have run.
-- The keys live in qss_nvim/octo-nvim/mappings.lua.

-- The keys that move between the files of a review, the same in the diff, in
-- the file panel and in the review submit window. They replace the octo
-- defaults ]q, [q, ]u, [u, [Q and ]Q.
local review_file_keys = {
    select_next_entry = { lhs = '<localleader>n', desc = 'next file' },
    select_prev_entry = { lhs = '<localleader>p', desc = 'previous file' },
    select_next_unviewed_entry = { lhs = '<localleader>u', desc = 'next unviewed file' },
    select_prev_unviewed_entry = { lhs = '<localleader>U', desc = 'previous unviewed file' },
    select_first_entry = { lhs = '<localleader>f', desc = 'first file' },
    select_last_entry = { lhs = '<localleader>F', desc = 'last file' },
    -- <Tab> and <S-Tab> switch barbar buffers everywhere else. In a review,
    -- they would load another buffer into a diff window, so they switch the
    -- review file instead. octo.nvim accepts one key per action, so config()
    -- adds these two actions to the octo.mappings table.
    select_next_entry_by_tab = { lhs = '<Tab>', desc = 'next file' },
    select_prev_entry_by_tab = { lhs = '<S-Tab>', desc = 'previous file' },
}

-- The key that goes from the diff or the file panel of a review to the pull
-- request buffer, and from the pull request buffer back to the review. The key
-- is the same in each of these buffers. config() adds the action to the
-- octo.mappings table.
local switch_review_tab = { lhs = '<localleader>gt', desc = 'switch between pull request and review' }

return {
    'pwntester/octo.nvim',
    cmd = 'Octo',
    dependencies = {
        'nvim-lua/plenary.nvim',
        'folke/snacks.nvim',
        'nvim-tree/nvim-web-devicons',
    },
    opts = {
        picker = 'snacks',
        -- `:Octo` with no argument opens a picker of every Octo action.
        enable_builtin = true,
        -- While the pull request branch is checked out, the right side of a
        -- review diff opens the file from disk, so the LSP server attaches.
        use_local_fs = true,
        -- octo stops each synchronous gh call after this many milliseconds.
        -- The octo default of 5000 ms is too short for `gh pr checkout` on a
        -- large repository, because the git fetch takes longer.
        timeout = 60000,
        -- The default delimiters are the Powerline rounded caps U+E0B6 and
        -- U+E0B4, which the terminal font draws badly. With one space, the
        -- bubble is a padded rectangle. after/plugin/colors.lua sets the colors.
        left_bubble_delimiter = ' ',
        right_bubble_delimiter = ' ',
        -- `:Octo review` with no subcommand resumes the pending review or
        -- starts one. The `:Octo` action picker lists only named subcommands,
        -- so `review open` gives the same action a line in the picker.
        commands = {
            review = {
                open = function() require('octo.reviews').start_or_resume_review() end,
            },
        },
        mappings = {
            review_diff = vim.tbl_extend('force', review_file_keys, { switch_review_tab = switch_review_tab }),
            file_panel = vim.tbl_extend('force', review_file_keys, { switch_review_tab = switch_review_tab }),
            submit_win = review_file_keys,
            -- In a pull request buffer, the review key (start or resume a
            -- review) does the work of review_start too. Without review_start,
            -- <localleader>rs means "submit review" in each Octo buffer that
            -- has it.
            pull_request = {
                review_start = { lhs = '' },
                -- config() adds this action to the octo.mappings table.
                goto_thread_in_diff = { lhs = '<localleader>gd', desc = 'go to thread in diff' },
                switch_review_tab = switch_review_tab,
            },
        },
    },
    config = function(_, opts)
        require('qss_nvim.octo-nvim.key_prefixes').apply(opts.mappings)
        require('octo').setup(opts)
        local actions = require('octo.mappings')
        actions.select_next_entry_by_tab = actions.select_next_entry
        actions.select_prev_entry_by_tab = actions.select_prev_entry
        actions.goto_thread_in_diff = require('qss_nvim.octo-nvim.thread_jump').jump
        actions.switch_review_tab = require('qss_nvim.octo-nvim.review_tab_switch').switch
        -- Octo buffers hold GitHub markdown, so the markdown parser
        -- highlights them.
        vim.treesitter.language.register('markdown', 'octo')
        require('qss_nvim.octo-nvim.review_order').setup()
        require('qss_nvim.octo-nvim.review_viewed').setup()
        require('qss_nvim.octo-nvim.review_windows').setup()
        require('qss_nvim.octo-nvim.review_buffers').setup()
        require('qss_nvim.octo-nvim.review_widths').setup()
        require('qss_nvim.octo-nvim.review_actions').setup()
        require('qss_nvim.octo-nvim.review_thread_folds').setup()
    end,
}
