-- lua/codex/terminal.lua
local M = {}

local active_provider = nil
local active_provider_name = nil
local active_config = nil

local NOOP_PROVIDER = {
  is_available = function() return true end,
  open = function() end,
  close = function() end,
  simple_toggle = function() end,
  focus_toggle = function() end,
  get_active_bufnr = function() return nil end,
}

local function resolve_provider(cfg)
  local terminal_cfg = cfg.terminal or {}
  local p = terminal_cfg.provider or "auto"

  if p == "none" then
    return NOOP_PROVIDER, "none"
  end

  if p == "external" then
    return require("codex.terminal.external"), "external"
  end

  local snacks = require("codex.terminal.snacks")
  local native = require("codex.terminal.native")

  if p == "snacks" then
    if snacks.is_available() then
      return snacks, "snacks"
    end
    vim.notify(
      "codex: snacks provider requested but snacks.nvim is not available, falling back to native",
      vim.log.levels.WARN
    )
    return native, "native"
  end

  if p == "native" then
    return native, "native"
  end

  -- "auto"
  if snacks.is_available() then
    return snacks, "snacks"
  end
  return native, "native"
end

function M.setup(config)
  active_config = config
  active_provider, active_provider_name = resolve_provider(config)
end

local function get_cmd()
  return active_config and active_config.codex_cmd or "codex"
end

local function get_opts()
  return active_config and active_config.terminal or {}
end

function M.open()
  if not active_provider then return end
  active_provider.open(get_cmd(), get_opts())
end

function M.close()
  if not active_provider then return end
  active_provider.close()
end

function M.simple_toggle()
  if not active_provider then return end
  active_provider.simple_toggle(get_cmd(), get_opts())
end

function M.focus_toggle()
  if not active_provider then return end
  active_provider.focus_toggle(get_cmd(), get_opts())
end

function M.get_active_terminal_bufnr()
  if not active_provider then return nil end
  return active_provider.get_active_bufnr()
end

---Send text into the terminal stdin (e.g. "@file:1-10 " for context injection).
---@param text string
function M.send_text(text)
  if active_provider and active_provider.send_text then
    active_provider.send_text(text)
  end
end

-- test helper
function M._get_active_provider_name()
  return active_provider_name
end

return M
