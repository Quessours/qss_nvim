local M = {}

---@class qss.lsp.Server
---@field name string the name that shows up in :checkhealth vim.lsp
---@field version string?
---@field capabilities lsp.ServerCapabilities
---@field handlers table<string, fun(params: table): any>

--- The `cmd` a vim.lsp.Config passes to nvim.
---@param server qss.lsp.Server
---@return fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient
function M.cmd(server)
    ---@type table<string, fun(params: table): any>
    local handlers = {
        initialize = function()
            return {
                capabilities = server.capabilities,
                serverInfo = { name = server.name, version = server.version or '1' },
            }
        end,
        shutdown = function()
            return vim.NIL
        end,
    }
    for method, handler in pairs(server.handlers) do
        handlers[method] = handler
    end

    ---@param dispatchers vim.lsp.rpc.Dispatchers
    ---@return vim.lsp.rpc.PublicClient
    return function(dispatchers)
        local closing = false
        local last_id = 0

        return {
            ---@param method string
            ---@param params table?
            ---@param callback fun(err?: lsp.ResponseError, result: any)
            ---@param notify_reply_callback? fun(message_id: integer)
            ---@return boolean, integer?
            request = function(method, params, callback, notify_reply_callback)
                if closing then
                    return false
                end

                last_id = last_id + 1
                local id = last_id
                local handler = handlers[method]

                vim.schedule(function()
                    if closing then
                        return
                    end

                    if not handler then
                        callback({ code = -32601, message = 'method not found: ' .. method }, nil)
                    else
                        local ok, result = pcall(handler, params)
                        if ok then
                            callback(nil, result)
                        else
                            callback({ code = -32603, message = tostring(result) }, nil)
                        end
                    end

                    if notify_reply_callback then
                        notify_reply_callback(id)
                    end
                end)

                return true, id
            end,

            ---@param method string
            ---@return boolean
            notify = function(method, _)
                if method == 'exit' then
                    closing = true
                    dispatchers.on_exit(0, 0)
                end
                return not closing
            end,

            is_closing = function()
                return closing
            end,

            terminate = function()
                if not closing then
                    closing = true
                    dispatchers.on_exit(0, 0)
                end
            end,
        }
    end
end

return M
