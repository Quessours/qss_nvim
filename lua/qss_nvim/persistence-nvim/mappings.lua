-- The dashboard restores a session on start. These keys do it in the middle of
-- a session, once buffers are already open.
--
-- persistence is required inside each mapping because this table is built in
-- init.lua before lazy has loaded a single plugin.
local function persistence()
    return require('persistence')
end

local M = {
    n = {
        ["<leader>Sr"] = { function() persistence().load() end, "Restore the session of this directory" },
        ["<leader>Sl"] = { function() persistence().load({ last = true }) end, "Restore the last session" },
        ["<leader>Ss"] = { function() persistence().select() end, "Select a session to restore" },
        ["<leader>Sd"] = { function() persistence().stop() end, "Do not save the current session" },
    }
}

return M
