-- A sign that a write is in flight.
--
-- Every change goes over the network, and the round trip is long enough to
-- wonder whether the key registered at all. Nothing was shown until the answer
-- came back, so a slow save and a dropped one looked the same.
local M = {}

local TITLE = 'Jira'

---@type table<integer, string>
local running = {}
local next_token = 0

local FRAMES = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local frame = 1
local timer

---@return string
local function summary()
    local labels = {}
    for _, label in pairs(running) do
        labels[#labels + 1] = label
    end
    table.sort(labels)
    return table.concat(labels, ', ')
end

local function draw()
    if not next(running) then
        return
    end
    frame = frame % #FRAMES + 1

    -- One notification, replaced in place: snacks keeps the id, so a save does
    -- not leave a trail of messages behind it.
    if Snacks and Snacks.notifier then
        Snacks.notifier.notify(('%s %s'):format(FRAMES[frame], summary()), 'info', {
            id = 'qss_jira_progress',
            title = TITLE,
            timeout = 2000,
        })
    end
end

local function stop_timer()
    if timer then
        timer:stop()
        timer:close()
        timer = nil
    end
end

--- Say that something is being written, and get a token back to end it with.
---@param label string
---@return integer token
function M.start(label)
    next_token = next_token + 1
    running[next_token] = label

    if not timer then
        timer = vim.uv.new_timer()
        if timer then
            timer:start(0, 120, vim.schedule_wrap(draw))
        end
    end
    return next_token
end

--- That one is done. The notification goes as soon as nothing is left.
---@param token integer?
function M.finish(token)
    if token == nil then
        return
    end
    running[token] = nil

    if next(running) then
        return
    end
    stop_timer()
    if Snacks and Snacks.notifier then
        Snacks.notifier.hide('qss_jira_progress')
    end
end

return M
