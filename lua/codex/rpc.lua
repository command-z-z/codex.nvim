local transport = require("codex.transport")

local M = {}
local Rpc = {}
Rpc.__index = Rpc

function M.connect(url, opts)
  opts = opts or {}
  local rpc = setmetatable({
    url = url,
    next_id = 1,
    pending = {},
    request_timeout_ms = opts.request_timeout_ms or 120000,
    on_open = opts.on_open,
    on_close = opts.on_close,
    on_error = opts.on_error,
    on_notification = opts.on_notification,
    on_request = opts.on_request,
  }, Rpc)

  local session, err = transport.new(url, {
    on_open = function()
      if rpc.on_open then rpc.on_open(rpc) end
    end,
    on_close = function()
      rpc:_fail_all("WebSocket closed")
      if rpc.on_close then rpc.on_close() end
    end,
    on_error = function(message)
      if rpc.on_error then rpc.on_error(message) end
    end,
    on_message = function(message)
      rpc:_handle_message(message)
    end,
  })

  if not session then
    return nil, err
  end

  session:connect()
  rpc.client = session
  return rpc, nil
end

function Rpc:_send(payload)
  local encoded = vim.json.encode(payload)
  return self.client:send(encoded)
end

function Rpc:_next_request_id()
  local id = self.next_id
  self.next_id = self.next_id + 1
  return id
end

function Rpc:request(method, params, callback, timeout_ms)
  local id = self:_next_request_id()
  local timer = (vim.uv or vim.loop).new_timer()

  timer:start(timeout_ms or self.request_timeout_ms, 0, function()
    vim.schedule(function()
      local pending = self.pending[id]
      if not pending then return end
      self.pending[id] = nil
      timer:stop()
      timer:close()
      if pending.callback then
        pending.callback(nil, { message = "Request timed out: " .. method })
      end
    end)
  end)

  self.pending[id] = { method = method, callback = callback, timer = timer }

  local ok, err = self:_send({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or vim.empty_dict(),
  })

  if not ok then
    self.pending[id] = nil
    timer:stop()
    timer:close()
    if callback then callback(nil, { message = err or "Failed to send request" }) end
  end

  return id
end

function Rpc:notify(method, params)
  return self:_send({
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  })
end

function Rpc:respond(id, result, error_data)
  local response = { jsonrpc = "2.0", id = id }
  if error_data then
    response.error = error_data
  else
    response.result = result or vim.empty_dict()
  end
  return self:_send(response)
end

function Rpc:_handle_message(message)
  local ok, decoded = pcall(vim.json.decode, message)
  if not ok or type(decoded) ~= "table" then
    if self.on_error then self.on_error("Invalid JSON-RPC message") end
    return
  end

  -- Response to our request
  if decoded.id and (decoded.result ~= nil or decoded.error ~= nil) then
    local pending = self.pending[decoded.id]
    if not pending then return end
    self.pending[decoded.id] = nil
    if pending.timer then pending.timer:stop(); pending.timer:close() end
    if pending.callback then pending.callback(decoded.result, decoded.error) end
    return
  end

  -- Server-initiated request (has id + method)
  if decoded.id and decoded.method then
    if self.on_request then
      self.on_request(decoded.method, decoded.params or {}, function(result, error_data)
        self:respond(decoded.id, result, error_data)
      end)
    else
      self:respond(decoded.id, nil, { code = -32601, message = "Method not found" })
    end
    return
  end

  -- Notification (method, no id)
  if decoded.method and self.on_notification then
    self.on_notification(decoded.method, decoded.params or {})
  end
end

function Rpc:_fail_all(message)
  for id, pending in pairs(self.pending) do
    self.pending[id] = nil
    if pending.timer then pending.timer:stop(); pending.timer:close() end
    if pending.callback then pending.callback(nil, { message = message }) end
  end
end

function Rpc:close()
  self:_fail_all("Connection closed")
  if self.client then self.client:close() end
end

return M
