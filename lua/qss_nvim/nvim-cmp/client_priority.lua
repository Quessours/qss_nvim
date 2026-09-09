local M = {}

--- The clients that rank above the rest, in the order they asked.
---@type table<string, number>
local ranks = {}

local declared = 0

--- Rank the items of a client above those of every client that has not asked.
---@param name string the name the client is registered under
function M.prefer(name)
    if ranks[name] then
        return
    end
    declared = declared + 1
    ranks[name] = declared
end

--- Where the client behind an entry ranks. A client that has not asked ranks
--- last, which is where every entry from a plain source lands too.
---@param entry table a cmp entry
---@return number
local function rank_of(entry)
    local source = entry.source.source
    local client = source and source.client
    if not client then
        return math.huge
    end
    local rank = ranks[client.name]
    return rank or math.huge
end

--- A cmp comparator. It answers nil for two entries of equal rank, which
--- leaves the order to the comparators behind it.
---@param left table
---@param right table
---@return boolean?
function M.compare(left, right)
    local left_rank, right_rank = rank_of(left), rank_of(right)
    if left_rank == right_rank then
        return nil
    end
    return left_rank < right_rank
end

return M
