-- A snacks picker of the open pull requests that wait for a review of the
-- current gh user and that have fewer than APPROVALS_NEEDED approvals. GitHub
-- search cannot count approvals, so the module asks the GraphQL API for the
-- latest review of each reviewer and counts the approvals itself.
local filters = require('qss_nvim.octo-nvim.filters')

local M = {}

local APPROVALS_NEEDED = 2

local SEARCH = 'is:pr is:open review-requested:@me archived:false'

-- latestOpinionatedReviews keeps the last approval or change request of each
-- reviewer, so a reviewer who approved and then asked for changes does not
-- count as an approval.
local QUERY = [[
query($q: String!) {
  search(query: $q, type: ISSUE, first: 100) {
    nodes {
      ... on PullRequest {
        number
        title
        isDraft
        author { login }
        repository { nameWithOwner }
        latestOpinionatedReviews(first: 100, writersOnly: true) {
          nodes { state author { login } }
        }
      }
    }
  }
}]]

---@param pr table A PullRequest node of the GraphQL search.
---@return string[] approvers The logins of the reviewers whose latest review approves the pull request.
local function approvers_of(pr)
    local approvers = {}
    for _, review in ipairs(pr.latestOpinionatedReviews.nodes) do
        if review.state == 'APPROVED' then
            approvers[#approvers + 1] = review.author and review.author.login or 'ghost'
        end
    end
    return approvers
end

---@param pr table A PullRequest node of the GraphQL search.
---@param approvers string[]
---@return table item A snacks picker item.
local function to_item(pr, approvers)
    local repo = pr.repository.nameWithOwner
    local author = pr.author and pr.author.login or 'ghost'
    local approved_by = #approvers > 0 and table.concat(approvers, ', ') or 'nobody'
    local preview = table.concat({
        '# ' .. pr.title,
        '',
        '- Repository: ' .. repo .. ' #' .. pr.number,
        '- Author: ' .. author,
        '- Draft: ' .. (pr.isDraft and 'yes' or 'no'),
        '- Approvals: ' .. #approvers .. ' / ' .. APPROVALS_NEEDED .. ' (' .. approved_by .. ')',
    }, '\n')
    return {
        text = repo .. ' #' .. pr.number .. ' ' .. pr.title .. ' ' .. author,
        repo = repo,
        number = pr.number,
        title = pr.title,
        approvals = #approvers,
        preview = { text = preview, ft = 'markdown' },
    }
end

---@param items table[]
local function show(items)
    if #items == 0 then
        vim.notify('No pull request waits for your review with fewer than '
            .. APPROVALS_NEEDED .. ' approvals', vim.log.levels.INFO)
        return
    end
    Snacks.picker.pick({
        title = filters.scoped_title('PRs that need my review'),
        items = items,
        preview = 'preview',
        format = function(item)
            return {
                { item.approvals .. '/' .. APPROVALS_NEEDED .. ' ', 'SnacksPickerLabel' },
                { item.repo .. ' ', 'SnacksPickerDir' },
                { '#' .. item.number .. ' ', 'Number' },
                { item.title },
            }
        end,
        confirm = function(picker, item)
            picker:close()
            vim.cmd(string.format('Octo %d %s', item.number, item.repo))
        end,
    })
end

function M.open()
    local cmd = { 'gh', 'api', 'graphql', '-f', 'q=' .. filters.scoped(SEARCH), '-f', 'query=' .. QUERY }
    vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
        if result.code ~= 0 then
            vim.notify('gh api graphql failed: ' .. result.stderr, vim.log.levels.ERROR)
            return
        end
        local response = vim.json.decode(result.stdout)
        local items = {}
        for _, pr in ipairs(response.data.search.nodes) do
            local approvers = approvers_of(pr)
            if #approvers < APPROVALS_NEEDED then
                items[#items + 1] = to_item(pr, approvers)
            end
        end
        show(items)
    end))
end

return M
