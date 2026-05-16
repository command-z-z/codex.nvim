-- lua/codex/codex_config_check.lua
-- Best-effort scanner for ~/.codex/config.toml that warns the user when
-- top-level approval_policy / sandbox_mode entries would silently bypass
-- the plugin's diff approval flow.
--
-- Codex CLI flag precedence is: CLI > profile > config.toml > default. The
-- plugin always passes --ask-for-approval and --sandbox via init.lua's
-- append_approval_args, so these config.toml values shouldn't override
-- ours. But many real-world configs have older defaults like
-- approval_policy = "never" that the user has forgotten about, and the
-- warning saves debugging time.
local M = {}

-- Minimal TOML scan: only top-level string assignments. Stops at the
-- first [section] header so we don't accidentally read project-scoped
-- entries (which use [projects."path"] tables).
function M.scan(path)
  local fd = io.open(path, "r")
  if not fd then return {} end
  local found = {}
  for line in fd:lines() do
    if line:match("^%s*%[") then break end
    local k, v = line:match('^%s*([%w_]+)%s*=%s*"([^"]+)"')
    if k == "approval_policy" or k == "sandbox_mode" then
      found[k] = v
    end
  end
  fd:close()
  return found
end

function M.warnings(found)
  local out = {}
  if found.approval_policy == "never" then
    out[#out + 1] =
      "~/.codex/config.toml has approval_policy='never' — this WILL bypass "
      .. "plugin diff approval. Remove it (or set 'on-request') to see diffs."
  end
  if found.sandbox_mode == "danger-full-access" then
    out[#out + 1] =
      "~/.codex/config.toml has sandbox_mode='danger-full-access' — edits "
      .. "will not require approval. Remove it to see diffs."
  end
  return out
end

function M.check_and_warn()
  local home = os.getenv("HOME") or ""
  if home == "" then return {} end
  local found = M.scan(home .. "/.codex/config.toml")
  for _, w in ipairs(M.warnings(found)) do
    vim.notify("codex: " .. w, vim.log.levels.WARN)
  end
  return found
end

return M
