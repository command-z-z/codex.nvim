-- lua/codex/handlers/approval.lua
local M = {}

M.APPROVAL_METHODS = {
  "item/commandExecution/requestApproval",
  "item/permissions/requestApproval",
  "item/fileChange/requestApproval",
  "applyPatchApproval",
  "item/tool/requestUserInput",
  "mcpServer/elicitation/request",
}

local function is_user_input(method)
  return method:find("requestUserInput", 1, true) ~= nil
    or method:find("elicitation", 1, true) ~= nil
end

function M._approve_result(method)
  if is_user_input(method) then
    return { decision = "confirmed" }
  end
  return { decision = "approved" }
end

function M._deny_result(method)
  if is_user_input(method) then
    return { decision = "declined" }
  end
  return { decision = "denied" }
end

function M._get_policy()
  local ok, init = pcall(require, "codex.init")
  if ok and init.state and init.state.config and init.state.config.approval then
    return init.state.config.approval.policy or "prompt"
  end
  return "prompt"
end

function M._prompt_user(method, params, respond)
  vim.schedule(function()
    local label = (params and (params.description or params.command or params.tool))
      or method
    local answer = vim.fn.confirm("codex: Allow " .. label .. "?", "&Allow\n&Deny", 2)
    if answer == 1 then
      respond(M._approve_result(method), nil)
    else
      respond(M._deny_result(method), nil)
    end
  end)
end

function M.handle(method, params, respond)
  local policy = M._get_policy()
  if policy == "auto-allow" then
    respond(M._approve_result(method), nil)
  elseif policy == "auto-deny" then
    respond(M._deny_result(method), nil)
  else
    M._prompt_user(method, params, respond)
  end
end

return M
