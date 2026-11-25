-- In a pull request buffer, jump() opens the review diff at the review thread
-- under the cursor. The `gf` key of octo.nvim opens the file from the working
-- tree instead.
--
-- If a tab already shows the review of the pull request, jump() switches to
-- that tab. Otherwise jump() resumes the pending review, or starts one, as
-- `:Octo review` does. octo.nvim loads the files and the threads of a new
-- review asynchronously, so a timer waits until the thread is known.
local M = {}

local POLL_INTERVAL_MS = 100
local POLL_TIMEOUT_MS = 10000

---@param repo string
---@param number integer
---@return table? review The open octo.nvim review of the pull request.
---@return integer? tabpage The tab that shows the review.
function M.find_review(repo, number)
    for tab_key, review in pairs(require('octo.reviews').reviews) do
        local pull_request = review.pull_request
        if pull_request.repo == repo and pull_request.number == number then
            return review, tonumber(tab_key)
        end
    end
    return nil, nil
end

---@param review table
---@return boolean
local function is_ready(review)
    return review.layout ~= nil and #review.layout.files > 0
end

---@param review table
---@param thread_id string
---@param path string
local function jump_in_review(review, thread_id, path)
    local thread = review.threads and review.threads[thread_id]
    if thread then
        require('octo.reviews').jump_to_pending_review_thread(thread)
        return
    end
    -- octo.nvim drops outdated threads from the review, so the jump can only
    -- open the file of such a thread.
    for _, file in ipairs(review.layout.files) do
        if file.path == path then
            review.layout:set_current_file(file)
            break
        end
    end
    vim.notify('The review has no current thread at the cursor: the thread is outdated',
        vim.log.levels.WARN)
end

function M.jump()
    local buffer = require('octo.utils').get_current_buffer()
    if not buffer or not buffer:isPullRequest() then
        return
    end
    local thread = buffer:get_thread_at_cursor()
    if not thread then
        vim.notify('No review thread at the cursor', vim.log.levels.WARN)
        return
    end
    local thread_id, path = thread.threadId, thread.path
    local repo, number = buffer.repo, buffer.number

    local open_review, tabpage = M.find_review(repo, number)
    if open_review and tabpage and vim.api.nvim_tabpage_is_valid(tabpage) and is_ready(open_review) then
        vim.api.nvim_set_current_tabpage(tabpage)
        jump_in_review(open_review, thread_id, path)
        return
    end

    require('octo.reviews').start_or_resume_review()
    local waited_ms = 0
    local timer = assert(vim.uv.new_timer())
    timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(function()
        if timer:is_closing() then
            return
        end
        waited_ms = waited_ms + POLL_INTERVAL_MS
        local review = M.find_review(repo, number)
        if review and is_ready(review) then
            timer:close()
            jump_in_review(review, thread_id, path)
        elseif waited_ms >= POLL_TIMEOUT_MS then
            timer:close()
            vim.notify('The review did not open in time: no jump to the thread', vim.log.levels.WARN)
        end
    end))
end

return M
