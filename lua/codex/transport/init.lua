local session = require("codex.transport.session")

---@class Transport
---Facade over transport.session. Consumers require("codex.transport") and call M.new().
local M = {}

---Create a new WebSocket session (not yet connected).
---@param url string  ws://host:port[/path]
---@param callbacks table|nil  { on_open, on_message, on_close, on_error }
---@return Session|nil session, string|nil error
function M.new(url, callbacks)
  return session.new(url, callbacks)
end

return M
