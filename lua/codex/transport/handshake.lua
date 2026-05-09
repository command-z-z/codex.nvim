local utils = require("codex.transport.utils")
local M = {}

---Parse a ws:// URL into host, port, path.
---@param url string
---@return table|nil parsed, string|nil error
function M.parse_url(url)
  local host, port, path = url:match("^ws://([^:/]+):(%d+)(/?.*)")
  if not host then
    return nil, "Only ws://host:port[/path] URLs are supported: " .. tostring(url)
  end
  if path == "" then path = "/" end
  return { host = host, port = tonumber(port), path = path }
end

---Build an HTTP/1.1 WebSocket upgrade request string.
---@param host string
---@param port number
---@param path string
---@param key string Base64-encoded 16-byte nonce
---@return string
function M.build_request(host, port, path, key)
  return table.concat({
    "GET " .. path .. " HTTP/1.1",
    "Host: " .. host .. ":" .. tostring(port),
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: " .. key,
    "Sec-WebSocket-Version: 13",
    "",
    "",
  }, "\r\n")
end

---Parse the server's HTTP upgrade response.
---@param response string The full HTTP response headers (including trailing \r\n\r\n)
---@return boolean ok, string accept_key_or_error
function M.parse_response(response)
  local status = response:match("^(HTTP/%d+%.%d+ %d+ [^\r\n]*)")
  if not status then
    return false, "Invalid HTTP response"
  end
  if not status:find(" 101 ", 1, true) then
    return false, "Expected 101 Switching Protocols, got: " .. status
  end
  -- Extract Sec-WebSocket-Accept (case-insensitive header name)
  local accept = response:match("[Ss]ec%-[Ww]eb[Ss]ocket%-[Aa]ccept:%s*([^\r\n]+)")
  return true, accept and (accept:gsub("%s+$", "")) or nil
end

---Validate the server's Sec-WebSocket-Accept against our client key.
---@param client_key string The key we sent in the upgrade request
---@param server_accept string The value the server returned
---@return boolean
function M.validate_accept(client_key, server_accept)
  local expected = utils.generate_accept_key(client_key)
  if not expected then return false end
  return expected == server_accept
end

return M
