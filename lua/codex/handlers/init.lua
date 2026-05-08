-- lua/codex/handlers/init.lua
local M = {}

local _handlers = {}

function M.register(method, handler)
  _handlers[method] = handler
end

function M.handle_notification(method, params)
  local h = _handlers[method]
  if h and h.on_notification then
    h.on_notification(params)
  end
end

function M.handle_request(method, params, respond)
  local h = _handlers[method]
  if h and h.on_request then
    h.on_request(params, respond)
  else
    if respond then
      respond(nil, { code = -32601, message = "Method not found: " .. tostring(method) })
    end
  end
end

function M.setup()
  local diff_apply = require("codex.handlers.diff_apply")
  M.register("$/codex/fileChange", diff_apply)
end

return M
