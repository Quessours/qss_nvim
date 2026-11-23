-- The pull request filters of the <leader>go keys, and a snacks picker that
-- lists them. Each <leader>go filter key and each line of the picker runs the
-- same filter from this list.
local M = {}

---@class qss.octo.Filter
---@field key string The key after <leader>go that runs the filter.
---@field label string
---@field detail string The GitHub search query, or how the filter selects its pull requests.
---@field run fun()

---@param query string A GitHub search query.
---@return fun()
local function octo_search(query)
    return function()
        vim.cmd('Octo search ' .. query)
    end
end

local MY_OPEN = 'is:pr is:open author:@me draft:false'
local MY_DRAFTS = 'is:pr is:open author:@me draft:true'
local WAIT_FOR_ME = 'is:pr is:open review-requested:@me'

---@type qss.octo.Filter[]
M.list = {
    { key = 'm', label = 'My open pull requests', detail = MY_OPEN, run = octo_search(MY_OPEN) },
    { key = 'd', label = 'My draft pull requests', detail = MY_DRAFTS, run = octo_search(MY_DRAFTS) },
    { key = 'v', label = 'Pull requests that wait for my review', detail = WAIT_FOR_ME, run = octo_search(WAIT_FOR_ME) },
    {
        key = 'q',
        label = 'Pull requests that need my review',
        detail = WAIT_FOR_ME .. ', fewer than 2 approvals',
        run = function() require('qss_nvim.octo-nvim.review_queue').open() end,
    },
}

function M.pick()
    local items = {}
    for _, filter in ipairs(M.list) do
        items[#items + 1] = { text = filter.label .. ' ' .. filter.detail, filter = filter }
    end
    Snacks.picker.pick({
        title = 'Pull request filters',
        items = items,
        layout = { preset = 'select' },
        format = function(item)
            return {
                { item.filter.key .. ' ', 'SnacksPickerLabel' },
                { item.filter.label .. '  ' },
                { item.filter.detail, 'SnacksPickerComment' },
            }
        end,
        confirm = function(picker, item)
            picker:close()
            item.filter.run()
        end,
    })
end

return M
