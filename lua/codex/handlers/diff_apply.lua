-- lua/codex/handlers/diff_apply.lua
local M = {}

local state = {
  by_item = {},
  by_turn = {},
}

local function split_lines(text)
  local lines = {}
  for line in (tostring(text or ""):gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

local function prefixed_path(prefix, path)
  if path == "/dev/null" then
    return path
  end
  return prefix .. tostring(path or "")
end

local function content_hunk(prefix, content)
  local lines = split_lines(content or "")
  local out = { string.format("@@ -0,0 +1,%d @@", #lines) }
  for _, line in ipairs(lines) do
    out[#out + 1] = prefix .. line
  end
  return table.concat(out, "\n") .. "\n"
end

local function change_to_patch(path, change)
  if type(change) ~= "table" then
    return ""
  end

  path = tostring(path or "")
  local change_type = change.type or (change.kind and change.kind.type)
  local move_path = change.move_path or (change.kind and change.kind.move_path)
  local new_path = move_path or path
  local diff_text = change.unified_diff or change.diff

  if type(diff_text) == "string" and diff_text:find("^diff %-%-git ") then
    return diff_text:sub(-1) == "\n" and diff_text or (diff_text .. "\n")
  end

  local out = {
    string.format("diff --git %s %s", prefixed_path("a/", path), prefixed_path("b/", new_path)),
  }

  if change_type == "add" then
    out[#out + 1] = "new file mode 100644"
    out[#out + 1] = "--- /dev/null"
    out[#out + 1] = "+++ " .. prefixed_path("b/", new_path)
    out[#out + 1] = content_hunk("+", change.content)
  elseif change_type == "delete" then
    out[#out + 1] = "deleted file mode 100644"
    out[#out + 1] = "--- " .. prefixed_path("a/", path)
    out[#out + 1] = "+++ /dev/null"
    out[#out + 1] = content_hunk("-", change.content)
  else
    if move_path then
      out[#out + 1] = "rename from " .. path
      out[#out + 1] = "rename to " .. move_path
    end
    if type(diff_text) == "string" and diff_text ~= "" then
      out[#out + 1] = diff_text:sub(-1) == "\n" and diff_text or (diff_text .. "\n")
    end
  end

  return table.concat(out, "\n")
end

local function file_changes_to_patch(file_changes)
  if type(file_changes) ~= "table" then
    return ""
  end
  local out = {}
  for path, change in pairs(file_changes) do
    local patch = change_to_patch(path, change)
    if patch ~= "" then
      out[#out + 1] = patch
    end
  end
  return table.concat(out, "\n")
end

local function update_changes_to_patch(changes)
  if type(changes) ~= "table" then
    return ""
  end
  local out = {}
  for _, change in ipairs(changes) do
    local patch = change_to_patch(change.path, change)
    if patch ~= "" then
      out[#out + 1] = patch
    end
  end
  return table.concat(out, "\n")
end

local function patch_from_params(params)
  local p = params or {}
  if type(p.patch) == "string" then return p.patch end
  if type(p.diff) == "string" then return p.diff end
  local patch = file_changes_to_patch(p.fileChanges or p.file_changes)
  if patch ~= "" then return patch end
  if p.itemId and state.by_item[p.itemId] then return state.by_item[p.itemId] end
  if p.item_id and state.by_item[p.item_id] then return state.by_item[p.item_id] end
  if p.turnId and state.by_turn[p.turnId] then return state.by_turn[p.turnId] end
  if p.turn_id and state.by_turn[p.turn_id] then return state.by_turn[p.turn_id] end
  return ""
end

local function translate_response(method, respond)
  if method ~= "item/fileChange/requestApproval" then
    return respond
  end
  return function(result, err)
    if err then
      respond(nil, err)
      return
    end
    local decision = result and result.decision
    if decision == "approved" then
      respond({ decision = "accept" }, nil)
    elseif decision == "denied" then
      respond({ decision = "decline" }, nil)
    else
      respond(result, nil)
    end
  end
end

local function approve_result(method)
  if method == "item/fileChange/requestApproval" then
    return { decision = "accept" }
  end
  return { decision = "approved" }
end

local function deny_result(method)
  if method == "item/fileChange/requestApproval" then
    return { decision = "decline" }
  end
  return { decision = "denied" }
end

local function approval_policy()
  local init = require("codex")
  return init.state.config
    and init.state.config.approval
    and init.state.config.approval.policy
    or "prompt"
end

local function diff_opts()
  local init = require("codex")
  return (init.state.config and init.state.config.diff_opts) or {}
end

function M.on_request(params, respond, method)
  local diff = require("codex.diff")
  method = method or "applyPatchApproval"
  local policy = approval_policy()
  if policy == "auto-allow" then
    if respond then respond(approve_result(method), nil) end
    return
  elseif policy == "auto-deny" then
    if respond then respond(deny_result(method), nil) end
    return
  end

  local patch = patch_from_params(params)
  if patch == "" then
    if respond then
      respond(deny_result(method), nil)
    end
    vim.notify("codex: file change approval did not include a diff", vim.log.levels.WARN)
    return
  end
  diff.open(patch, respond and translate_response(method, respond) or nil, diff_opts())
end

function M.on_notification(params, method)
  local diff = require("codex.diff")
  local p = params or {}
  local patch
  if method == "turn/diff/updated" then
    patch = p.diff or p.patch or ""
  elseif method == "item/fileChange/patchUpdated" then
    patch = update_changes_to_patch(p.changes)
  else
    patch = patch_from_params(p)
  end
  if patch == "" then return end
  if p.itemId then state.by_item[p.itemId] = patch end
  if p.item_id then state.by_item[p.item_id] = patch end
  if p.turnId then state.by_turn[p.turnId] = patch end
  if p.turn_id then state.by_turn[p.turn_id] = patch end
  diff.open(patch, nil, diff_opts())
end

return M
