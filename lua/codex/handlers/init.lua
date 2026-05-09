-- lua/codex/handlers/init.lua
local M = {}

local _handlers = {}

local _setup_done = false

function M.register(method, handler)
  _handlers[method] = handler
end

function M.handle_notification(method, params)
  local h = _handlers[method]
  if h and h.on_notification then
    h.on_notification(params, method)
  end
end

function M.has_handler(method)
  return _handlers[method] ~= nil
end

function M.handle_request(method, params, respond)
  local h = _handlers[method]
  if h and h.on_request then
    h.on_request(params, respond, method)
  else
    if respond then
      respond(nil, { code = -32601, message = "Method not found: " .. tostring(method) })
    end
  end
end

function M.setup()
  if _setup_done then return end
  _setup_done = true

  local diff_apply = require("codex.handlers.diff_apply")
  M.register("applyPatchApproval", diff_apply)
  M.register("item/fileChange/requestApproval", diff_apply)
  M.register("turn/diff/updated", diff_apply)
  M.register("item/fileChange/patchUpdated", diff_apply)

  local approval = require("codex.handlers.approval")
  for _, method in ipairs(approval.APPROVAL_METHODS) do
    local m = method
    M.register(m, {
      on_request = function(params, respond)
        approval.handle(m, params, respond)
      end,
    })
  end
end

return M
