-- lua/codex/handlers/diff_apply.lua
local M = {}

function M.on_request(params, respond)
  local diff = require("codex.diff")
  local init = require("codex.init")
  local opts = (init.state.config and init.state.config.diff_opts) or {}
  local patch = params.patch or params.diff or ""
  diff.open(patch, respond, opts)
end

function M.on_notification(params)
  local diff = require("codex.diff")
  local patch = params.patch or params.diff or ""
  diff.open(patch, nil, {})
end

return M
