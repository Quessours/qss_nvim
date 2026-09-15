-- Links between issues: blocks, is blocked by, has to be done after, and the
-- fifteen other relations this instance defines.
--
-- A link is one object seen from two sides. Viewing LIS-2311 it reads
-- `outwardIssue: LIS-2228`, and viewing LIS-2228 the same link reads
-- `inwardIssue: LIS-2311`. Both were checked against the live instance. The rule
-- that follows: the side carrying `outwardIssue` is the subject of the outward
-- phrase, so `inwardIssue` blocks `outwardIssue`, and a link is created by
-- naming which issue sits on which side.
local M = {}

local TITLE = 'Jira'

local cache = require('qss_nvim.jira.cache')
local http = require('qss_nvim.jira.http')

-- A day: an instance gains a link type about as often as it gains a project.
local TYPES_TTL = 86400

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify(message, level, { title = TITLE })
end

---@class qss.jira.Link
---@field id string
---@field phrase string how it reads from the issue being looked at
---@field other string the key on the far side
---@field summary string
---@field status string

--- The links of an issue, phrased from that issue's point of view.
---@param fields table
---@return qss.jira.Link[]
function M.of(fields)
    local links = {}

    for _, link in ipairs(fields.issuelinks or {}) do
        local outward = link.outwardIssue
        local far = outward or link.inwardIssue
        if far then
            local other_fields = far.fields or {}
            links[#links + 1] = {
                id = link.id,
                phrase = outward and link.type.outward or link.type.inward,
                other = far.key,
                summary = other_fields.summary or '',
                status = other_fields.status and other_fields.status.name or '',
            }
        end
    end

    table.sort(links, function(left, right)
        if left.phrase ~= right.phrase then
            return left.phrase < right.phrase
        end
        return left.other < right.other
    end)
    return links
end

--- Every relation the instance defines, each in both directions, because
--- "blocks" and "is blocked by" are two different things to say.
---@param callback fun(relations: { text: string, type_name: string, outward: boolean }[])
local function relations(callback)
    local remembered = cache.get('link.types')
    if remembered then
        return callback(remembered)
    end

    http.jira_rest('/rest/api/3/issueLinkType', function(decoded)
        local kinds = decoded.issueLinkTypes or {}
        if #kinds == 0 then
            return notify('this instance defines no link type', vim.log.levels.WARN)
        end

        local found = {}
        for _, kind in ipairs(kinds) do
            found[#found + 1] = { text = kind.outward, type_name = kind.name, outward = true }
            if kind.inward ~= kind.outward then
                found[#found + 1] = { text = kind.inward, type_name = kind.name, outward = false }
            end
        end

        table.sort(found, function(left, right)
            return left.text < right.text
        end)
        cache.set('link.types', found, TYPES_TTL)
        callback(found)
    end)
end

--- Link an issue to another one.
---@param key string
---@param done fun()?
function M.add(key, done)
    relations(function(found)
        local items = {}
        for index, relation in ipairs(found) do
            items[#items + 1] = {
                text = ('%s %s …'):format(key, relation.text),
                relation = relation,
                idx = index,
            }
        end

        Snacks.picker({
            source = 'jira_link_types',
            items = items,
            format = 'text',
            title = ('Link %s'):format(key),
            layout = { preset = 'select' },
            confirm = function(picker, item)
                picker:close()
                if not item then
                    return
                end

                require('qss_nvim.jira.issue').find(function(other)
                    if other == key then
                        return notify('an issue can not be linked to itself', vim.log.levels.WARN)
                    end

                    local relation = item.relation
                    local body = {
                        type = { name = relation.type_name },
                        inwardIssue = { key = relation.outward and key or other },
                        outwardIssue = { key = relation.outward and other or key },
                    }

                    http.jira_post('/rest/api/3/issueLink', body, function()
                        require('qss_nvim.jira.edit').landed(key)
                        notify(('%s %s %s'):format(key, relation.text, other), vim.log.levels.INFO)
                        if done then
                            done()
                        end
                    end)
                end)
            end,
        })
    end)
end

--- What to do with one link: follow it, or cut it.
---@param key string
---@param link qss.jira.Link
---@param done fun()?
function M.menu(key, link, done)
    local items = {
        { text = ('Go to %s  (or gd on the line)'):format(link.other), idx = 1, run = function()
            require('qss_nvim.jira.issue').open(link.other)
        end },
        { text = ('Remove this link (%s %s %s)'):format(key, link.phrase, link.other), idx = 2, run = function()
            http.jira_delete(('/rest/api/3/issueLink/%s'):format(link.id), function()
                require('qss_nvim.jira.edit').landed(key)
                notify(('%s no longer %s %s'):format(key, link.phrase, link.other), vim.log.levels.INFO)
                if done then
                    done()
                end
            end)
        end },
        { text = ('Link %s to another issue'):format(key), idx = 3, run = function()
            M.add(key, done)
        end },
    }

    Snacks.picker({
        source = 'jira_link',
        items = items,
        format = 'text',
        title = ('%s %s %s'):format(key, link.phrase, link.other),
        layout = { preset = 'select' },
        confirm = function(picker, item)
            picker:close()
            if item then
                item.run()
            end
        end,
    })
end

--- Pick a link to act on, for a caller with no line under the cursor.
---@param key string
---@param done fun()?
function M.pick(key, done)
    require('qss_nvim.jira.cli').json({ 'issue', 'view', key }, function(issue)
        local links = M.of(issue.fields or {})
        if #links == 0 then
            return M.add(key, done)
        end

        local items = {}
        for index, link in ipairs(links) do
            items[#items + 1] = {
                text = ('%-26s %-11s %s'):format(link.phrase, link.other, link.summary),
                link = link,
                idx = index,
            }
        end
        items[#items + 1] = { text = 'add a link', add = true, idx = #items + 1 }

        Snacks.picker({
            source = 'jira_links',
            items = items,
            format = 'text',
            title = ('Links of %s'):format(key),
            layout = { preset = 'select' },
            confirm = function(picker, item)
                picker:close()
                if not item then
                    return
                end
                if item.add then
                    return M.add(key, done)
                end
                M.menu(key, item.link, done)
            end,
        })
    end)
end

return M
