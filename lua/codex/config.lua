local M = {}

M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  codex_cmd = "codex",
  env = {},
  log_level = "info",
  track_selection = true,
  visual_demotion_delay_ms = 50,
  focus_after_send = false,
  connection_wait_delay = 600,
  connection_timeout = 10000,
  queue_timeout = 5000,
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false,
    keep_terminal_focus = false,
    on_new_file_reject = "keep_empty",
    hunk_level_review = true,
  },
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_percentage = 0.30,
    snacks_win_opts = {},
    auto_close = true,
    cwd_provider = nil,
    git_repo_cwd = true,
    provider_opts = { external_terminal_cmd = nil },
  },
  approval = {
    policy = "prompt",
    -- read-only forces codex to request approval for every edit, matching
    -- claudecode.nvim's per-edit diff UX. workspace-write is Codex's "Auto
    -- preset" — it silently auto-applies in-workspace edits and never
    -- triggers the plugin's approval flow.
    sandbox = "read-only",
  },
  models = {},
}

local function deep_copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and deep_copy(v) or v
  end
  return c
end

local function deep_merge(base, override)
  local result = deep_copy(base)
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.apply(user_config)
  return deep_merge(M.defaults, user_config or {})
end

local VALID_PROVIDERS = { auto = true, snacks = true, native = true, external = true, none = true }
local VALID_POLICIES  = { prompt = true, ["auto-deny"] = true, ["auto-allow"] = true }

function M.validate(cfg)
  if type(cfg) ~= "table" then
    error("validate: cfg must be a table, got " .. type(cfg))
  end
  if cfg.codex_cmd ~= nil and type(cfg.codex_cmd) ~= "string" then
    error("codex_cmd must be a string, got " .. type(cfg.codex_cmd))
  end
  if cfg.terminal and cfg.terminal.provider ~= nil then
    if not VALID_PROVIDERS[cfg.terminal.provider] then
      error("terminal.provider must be one of: auto, snacks, native, external, none. Got: " .. tostring(cfg.terminal.provider))
    end
  end
  if cfg.approval and cfg.approval.policy ~= nil then
    if not VALID_POLICIES[cfg.approval.policy] then
      error("approval.policy must be one of: prompt, auto-deny, auto-allow. Got: " .. tostring(cfg.approval.policy))
    end
  end
end

return M
