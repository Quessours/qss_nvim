-- switch() moves between a pull request buffer and the tab that shows the
-- review of the same pull request:
--   * In the diff or the file panel of a review, switch() goes to a window that
--     shows the pull request buffer. If no window shows that buffer, switch()
--     opens the pull request in a new tab.
--   * In a pull request buffer, switch() goes to the tab that shows the review
--     of the pull request. If no tab shows that review, switch() resumes the
--     pending review or starts one, as `:Octo review` does.
local M = {}

---@param repo string
---@param number integer
---@return integer? window A window that shows the octo.nvim buffer of the pull request.
local function find_pull_request_window(repo, number)
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        -- octo.nvim creates the global table octo_buffers when it loads.
        ---@diagnostic disable-next-line: undefined-field
        local buffer = _G.octo_buffers[vim.api.nvim_win_get_buf(window)]
        if buffer and buffer:isPullRequest() and buffer.repo == repo and buffer.number == number then
            return window
        end
    end
    return nil
end

---@param review table The octo.nvim review of the current tab.
local function to_pull_request(review)
    local pull_request = review.pull_request
    local window = find_pull_request_window(pull_request.repo, pull_request.number)
    if window then
        vim.api.nvim_set_current_win(window)
        return
    end
    vim.cmd('tabnew')
    vim.cmd(string.format('Octo %d %s', pull_request.number, pull_request.repo))
end

---@param buffer table The octo.nvim buffer of a pull request.
local function to_review(buffer)
    local review, tabpage = require('qss_nvim.octo-nvim.thread_jump').find_review(buffer.repo, buffer.number)
    if review and tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
        vim.api.nvim_set_current_tabpage(tabpage)
        return
    end
    require('octo.reviews').start_or_resume_review()
end

function M.switch()
    local review = require('octo.reviews').get_current_review()
    if review then
        to_pull_request(review)
        return
    end
    local buffer = require('octo.utils').get_current_buffer()
    if buffer and buffer:isPullRequest() then
        to_review(buffer)
    end
end

return M
