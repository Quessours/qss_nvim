-- kas and bitbake support: the :Kas* commands, the pickers and the keys.
--
-- Nothing here starts a container or reads a layer. The modules behind these
-- entry points answer from the layer files and from the cache, and only a
-- refresh or a build runs kas itself.
--
-- None of it means anything outside a kas project, so the commands and the keys
-- are created on entering one rather than at startup, gated on project.root the
-- way the overseer templates already are. :KasDoctor is the exception: what it
-- reports is why a directory was not recognised as a project, and a command
-- that exists only inside one cannot answer that.

vim.api.nvim_create_user_command('KasDoctor', function()
    require('qss_nvim.kas.doctor').report()
end, { desc = 'Check the kas setup' })

--- Everything a project brings: the commands, the keys, and the which-key group
--- that labels them.
local function enable()
    require('qss_nvim.kas.commands').setup()
    require('qss_nvim.utils').apply_mappings(require('qss_nvim.kas.mappings'))

    -- which-key queues a spec until it has loaded itself, so this works
    -- whichever of the two comes first.
    require('which-key').add({ { '<leader>k', group = 'kas' } })
end

vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'DirChanged' }, {
    desc = 'Enable the kas commands and keys inside a kas project',
    callback = function()
        -- No argument, so the directory nvim runs in decides and the buffer is
        -- only the fallback, which is how every other caller resolves it. The
        -- answer is memoized per directory, so the repeated BufEnter costs a
        -- table lookup.
        local root = require('qss_nvim.kas.project').root()
        if not root then
            return
        end

        enable()
        -- Deletes this autocommand. The commands stay for the rest of the
        -- session, the way they would have had init.lua created them.
        return true
    end,
})
