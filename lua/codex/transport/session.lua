local tcp_mod = require("codex.transport.tcp")
local handshake = require("codex.transport.handshake")
local frame = require("codex.transport.frame")
local utils = require("codex.transport.utils")

local M = {}
local Session = {}
Session.__index = Session

local PING_INTERVAL_MS = 30000

---Create a new session (not yet connected).
---@param url string  ws://host:port[/path]
---@param callbacks table|nil  { on_open, on_message, on_close, on_error }
---@return Session|nil session, string|nil error
function M.new(url, callbacks)
  local parsed, err = handshake.parse_url(url)
  if not parsed then
    return nil, err
  end
  return setmetatable({
    url = url,
    parsed = parsed,
    callbacks = callbacks or {},
    state = "idle",
    buffer = "",
    handshake_buffer = "",
    ws_key = nil,
    conn = nil,
    ping_timer = nil,
  }, Session)
end

---Connect to the server. Transitions idle/closed → connecting.
function Session:connect()
  if self.state ~= "idle" and self.state ~= "closed" then return end
  self.state = "connecting"
  self.ws_key = utils.generate_websocket_key()

  -- pending_upgrade holds the HTTP request when on_connect fires before
  -- new_connection() returns (synchronous mock). Once self.conn is assigned we
  -- flush it immediately below.
  local pending_upgrade = nil

  self.conn = tcp_mod.new_connection(self.parsed.host, self.parsed.port, {
    on_connect = function()
      self.state = "handshaking"
      self.handshake_buffer = ""
      local req = handshake.build_request(
        self.parsed.host, self.parsed.port, self.parsed.path, self.ws_key
      )
      if self.conn then
        self.conn:write(req)
      else
        -- on_connect fired synchronously before new_connection() returned;
        -- stash the request and flush it right after self.conn is assigned.
        pending_upgrade = req
      end
    end,
    on_data = function(data) self:_on_data(data) end,
    on_close = function() self:_on_disconnect() end,
    on_error = function(e) self:_on_error(e) end,
  })

  -- Flush any upgrade request that was stashed because on_connect fired early.
  if pending_upgrade then
    self.conn:write(pending_upgrade)
  end
end

---Send a text message. Only valid in open state.
---@param text string
---@return boolean ok, string|nil error
function Session:send(text)
  if self.state ~= "open" then
    return false, "session not open (state=" .. self.state .. ")"
  end
  -- client→server frames must be masked per RFC 6455
  local f = frame.create_frame(frame.OPCODE.TEXT, text, true, true)
  self.conn:write(f)
  return true
end

---Initiate a clean close handshake.
function Session:close()
  if self.state ~= "open" then return end
  self.state = "closing"
  self:_stop_heartbeat()
  self.conn:write(frame.create_close_frame())
end

-- Internal: called with raw bytes from the TCP layer.
function Session:_on_data(data)
  if self.state == "handshaking" then
    self.handshake_buffer = self.handshake_buffer .. data
    local header_end = self.handshake_buffer:find("\r\n\r\n", 1, true)
    if not header_end then return end

    local response = self.handshake_buffer:sub(1, header_end + 3)
    local remaining = self.handshake_buffer:sub(header_end + 4)
    local ok, accept = handshake.parse_response(response)
    if not ok then
      self:_on_error("WebSocket handshake failed: " .. tostring(accept))
      return
    end

    self.state = "open"
    self.buffer = remaining
    self:_start_heartbeat()
    if self.callbacks.on_open then self.callbacks.on_open() end
    if #remaining > 0 then self:_process_frames() end

  elseif self.state == "open" or self.state == "closing" then
    self.buffer = self.buffer .. data
    self:_process_frames()
  end
end

function Session:_process_frames()
  while #self.buffer >= 2 do
    local f, consumed = frame.parse_frame(self.buffer)
    if not f then break end
    self.buffer = self.buffer:sub(consumed + 1)
    self:_handle_frame(f)
  end
end

function Session:_handle_frame(f)
  if f.opcode == frame.OPCODE.TEXT then
    if self.callbacks.on_message then
      self.callbacks.on_message(f.payload)
    end
  elseif f.opcode == frame.OPCODE.PING then
    -- respond to server PINGs immediately (client→server pong must also be masked)
    self.conn:write(frame.create_frame(frame.OPCODE.PONG, f.payload, true, true))
  elseif f.opcode == frame.OPCODE.PONG then
    -- heartbeat acknowledged; nothing to do
  elseif f.opcode == frame.OPCODE.CLOSE then
    self:_stop_heartbeat()
    -- echo close frame back, then close
    self.conn:write(frame.create_frame(frame.OPCODE.CLOSE, f.payload, true, true))
    self.conn:close()
    self.state = "closed"
    if self.callbacks.on_close then self.callbacks.on_close() end
  end
end

function Session:_start_heartbeat()
  local uv = vim.uv or vim.loop
  self.ping_timer = uv.new_timer()
  self.ping_timer:start(PING_INTERVAL_MS, PING_INTERVAL_MS, function()
    vim.schedule(function()
      if self.state == "open" then
        -- masked ping from client
        self.conn:write(frame.create_frame(frame.OPCODE.PING, "", true, true))
      end
    end)
  end)
end

function Session:_stop_heartbeat()
  if self.ping_timer then
    pcall(function()
      self.ping_timer:stop()
      self.ping_timer:close()
    end)
    self.ping_timer = nil
  end
end

function Session:_on_disconnect()
  self:_stop_heartbeat()
  self.state = "closed"
  if self.callbacks.on_close then self.callbacks.on_close() end
end

function Session:_on_error(err)
  self:_stop_heartbeat()
  if self.conn then
    pcall(function() self.conn:close() end)
  end
  self.state = "closed"
  if self.callbacks.on_error then self.callbacks.on_error(err) end
end

return M
