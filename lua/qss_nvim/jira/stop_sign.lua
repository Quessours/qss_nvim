-- The stop sign a standup shows when the person speaking runs out of time.
--
-- A float that never takes the focus, so the board stays usable under it. It
-- swaps colors, words and position on a timer until it is hushed. <Esc> hushes
-- it from any window: the key is watched with vim.on_key rather than mapped, so
-- whatever <Esc> already does stays as it was.
local M = {}

local TICK = 200
local WIDTH = 21
-- How many ticks one pair of words stays up.
local WORDS_EVERY = 4

local namespace = vim.api.nvim_create_namespace('qss.jira.stop_sign')

local WORDS = {
    { 'S T O P !', 'standup time' },
    { 'STAND  UP', 'yes, you' },
    { '! P O T S', 'mirror mode' },
    { '¯\\_(ツ)_/¯', 'it is time' },
    { 'BEEP BEEP', 'coffee later' },
}

local COLORS = { 'QssStopSignRed', 'QssStopSignWhite', 'QssStopSignRed', 'QssStopSignYellow' }
local WOBBLE = { { 0, 0 }, { 0, 2 }, { -1, 0 }, { 0, -2 } }

---@type { window: integer, buffer: integer, timer: uv.uv_timer_t, tick: integer }?
local shown

local function define_colors()
    vim.api.nvim_set_hl(0, 'QssStopSignRed', { fg = '#ffffff', bg = '#cc0000', bold = true, default = true })
    vim.api.nvim_set_hl(0, 'QssStopSignWhite', { fg = '#cc0000', bg = '#ffffff', bold = true, default = true })
    vim.api.nvim_set_hl(0, 'QssStopSignYellow', { fg = '#000000', bg = '#ffcc00', bold = true, default = true })
end

---@param text string
---@param width integer
---@return string
local function center(text, width)
    local room = math.max(0, width - vim.fn.strdisplaywidth(text))
    local left = math.floor(room / 2)
    return (' '):rep(left) .. text .. (' '):rep(room - left)
end

---@param words string[]
---@return string[]
local function sign(words)
    return {
        '     ___________     ',
        '    /           \\    ',
        '   /             \\   ',
        '  |' .. center(words[1], 15) .. '|  ',
        '  |' .. center(words[2], 15) .. '|  ',
        '   \\             /   ',
        '    \\___________/    ',
        '         | |         ',
        '         | |         ',
        '      ___|_|___      ',
    }
end

---@param tick integer
---@return vim.api.keyset.win_config
local function placement(tick)
    local height = #sign(WORDS[1])
    local wobble = WOBBLE[tick % #WOBBLE + 1]
    return {
        relative = 'editor',
        row = math.max(0, math.floor((vim.o.lines - height) / 2) + wobble[1]),
        col = math.max(0, math.floor((vim.o.columns - WIDTH) / 2) + wobble[2]),
    }
end

local function frame()
    if not (shown and vim.api.nvim_win_is_valid(shown.window)) then
        return M.hide()
    end
    shown.tick = shown.tick + 1
    local tick = shown.tick

    local words = WORDS[math.floor(tick / WORDS_EVERY) % #WORDS + 1]
    vim.bo[shown.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(shown.buffer, 0, -1, false, sign(words))
    vim.bo[shown.buffer].modifiable = false

    local color = COLORS[tick % #COLORS + 1]
    vim.wo[shown.window].winhighlight = ('Normal:%s'):format(color)
    vim.api.nvim_win_set_config(shown.window, placement(tick))
end

function M.showing()
    return shown ~= nil
end

function M.show()
    if shown then
        return
    end
    define_colors()

    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].bufhidden = 'wipe'
    local lines = sign(WORDS[1])
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

    local config = placement(0)
    config.width = WIDTH
    config.height = #lines
    config.style = 'minimal'
    config.focusable = false
    config.noautocmd = true
    config.zindex = 250
    local window = vim.api.nvim_open_win(buffer, false, config)

    local timer = assert(vim.uv.new_timer())
    shown = { window = window, buffer = buffer, timer = timer, tick = 0 }
    timer:start(0, TICK, vim.schedule_wrap(frame))

    vim.on_key(function(key, typed)
        if key == '\27' or typed == '\27' then
            vim.schedule(M.hide)
        end
    end, namespace)
end

function M.hide()
    if not shown then
        return
    end
    local current = shown
    shown = nil

    vim.on_key(nil, namespace)
    current.timer:close()
    if vim.api.nvim_win_is_valid(current.window) then
        vim.api.nvim_win_close(current.window, true)
    end
end

return M
