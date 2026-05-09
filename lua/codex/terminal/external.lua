-- lua/codex/terminal/external.lua
local M = {}

local jobid = nil

function M.is_available(opts)
  opts = opts or {}
  local ext_cmd = opts.provider_opts and opts.provider_opts.external_terminal_cmd
  return ext_cmd ~= nil
end

function M.get_active_bufnr()
  return nil
end

function M.open(cmd, opts)
  if jobid then return end  -- already running
  opts = opts or {}
  local ext_cmd = opts.provider_opts and opts.provider_opts.external_terminal_cmd
  if not ext_cmd then
    vim.notify("codex: external_terminal_cmd not configured", vim.log.levels.WARN)
    return
  end

  local launch_cmd
  if type(ext_cmd) == "function" then
    launch_cmd = ext_cmd(cmd)
  else
    launch_cmd = string.format(ext_cmd, cmd)
  end

  jobid = vim.fn.jobstart(launch_cmd, { detach = true })
end

function M.close()
  if jobid then
    pcall(vim.fn.jobstop, jobid)
    jobid = nil
  end
end

function M.simple_toggle(cmd, opts)
  if jobid then
    M.close()
  else
    M.open(cmd, opts)
  end
end

function M.focus_toggle(cmd, opts)
  -- external terminals can't be focused programmatically; just open
  M.open(cmd, opts)
end

function M.ensure_visible()
  -- no-op: cannot control external window position
end

return M
