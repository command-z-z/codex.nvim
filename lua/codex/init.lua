-- lua/codex/init.lua
local M = {}

M.state = {
  config = nil,
  rpc = nil,
  port = nil,
  initialized = false,
  mention_queue = {},
  mention_timer = nil,
  connection_timer = nil,
  selected_model = nil,
}

local function is_connected()
  return M.state.rpc ~= nil
end

local ensure_app_server

local function approval_policy_for_cli(policy)
  if policy == "prompt" or policy == "auto-allow" or policy == "auto-deny" then
    return "on-request"
  end
  return policy or "on-request"
end

local function append_approval_args(cmd)
  local approval = (M.state.config and M.state.config.approval) or {}
  local policy = approval_policy_for_cli(approval.policy)
  cmd[#cmd + 1] = "--ask-for-approval"
  cmd[#cmd + 1] = policy

  local sandbox = approval.sandbox or "workspace-write"
  if sandbox and sandbox ~= "" then
    cmd[#cmd + 1] = "--sandbox"
    cmd[#cmd + 1] = sandbox
  end
end

local function build_codex_cmd(flag)
  local base = (M.state.config and M.state.config.codex_cmd) or "codex"
  local url = require("codex.app_server").url()
  if not url then return nil end
  local cmd
  if flag == "--resume" or flag == "--continue" then
    cmd = { base, "resume", "--last" }
  else
    cmd = { base }
  end
  append_approval_args(cmd)
  cmd[#cmd + 1] = "--remote"
  cmd[#cmd + 1] = url
  return cmd
end

local function flush_mentions()
  if #M.state.mention_queue == 0 then
    return
  end
  local terminal = require("codex.terminal")
  local now = vim.loop.now()
  local queue = {}
  for _, item in ipairs(M.state.mention_queue) do
    if item.expires_at > now then
      table.insert(queue, item.text)
    end
  end
  M.state.mention_queue = {}

  if #queue == 0 then return end

  local function send_all()
    for _, text in ipairs(queue) do
      terminal.send_text("@" .. text .. " ")
    end
  end

  if terminal.get_active_terminal_bufnr() then
    send_all()
  else
    ensure_app_server(function(cmd, err)
      if err then
        vim.notify("codex: app-server not ready — cannot open terminal for mention: " .. tostring(err), vim.log.levels.WARN)
        return
      end
      if not cmd then
        vim.notify("codex: app-server URL is not available", vim.log.levels.WARN)
        return
      end
      terminal.open(cmd)
      vim.defer_fn(send_all, 1500)
    end)
  end
end

local function schedule_flush()
  M.state.mention_timer = vim.defer_fn(flush_mentions, 50)
end

function M.enqueue_mention(text)
  local timeout = (M.state.config and M.state.config.queue_timeout) or 5000
  table.insert(M.state.mention_queue, {
    text = text,
    expires_at = vim.loop.now() + timeout,
  })
  schedule_flush()
end

local function on_connected(rpc)
  M.state.rpc = rpc
  if M.state.config and M.state.config.track_selection then
    local selection = require("codex.selection")
    selection.enable(rpc, M.state.config.visual_demotion_delay_ms)
  end
  if #M.state.mention_queue > 0 then
    schedule_flush()
  end
end

ensure_app_server = function(callback)
  local app_server = require("codex.app_server")
  app_server.ensure(function(rpc, err)
    if err then
      callback(nil, err)
      return
    end
    if rpc and not is_connected() then
      on_connected(rpc)
    end
    callback(build_codex_cmd(), nil)
  end)
end

local function start_server()
  local app_server = require("codex.app_server")
  local handlers = require("codex.handlers.init")
  handlers.setup()

  app_server.ensure(function(rpc, err)
    if err or not rpc then
      vim.notify("codex: failed to connect — " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    on_connected(rpc)
  end)
end

local function create_commands()
  local terminal = require("codex.terminal")

  local function open_codex_terminal(flag, mode)
    if terminal.get_active_terminal_bufnr() then
      if mode == "toggle" then
        terminal.simple_toggle()
      elseif mode == "focus" then
        terminal.focus_toggle()
      else
        terminal.open()
      end
      return
    end

    local app_server = require("codex.app_server")
    app_server.ensure(function(rpc, err)
      if err then
        vim.notify("codex: app-server not ready — " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      if rpc and not is_connected() then
        on_connected(rpc)
      end
      local cmd = build_codex_cmd(flag)
      if not cmd then
        vim.notify("codex: app-server URL is not available", vim.log.levels.ERROR)
        return
      end
      vim.schedule(function()
        if mode == "focus" then
          terminal.focus_toggle(cmd)
        else
          terminal.open(cmd)
        end
      end)
    end)
  end

  vim.api.nvim_create_user_command("Codex", function(args)
    local arg = (args.args or ""):match("^%s*(.-)%s*$")
    open_codex_terminal(arg, "toggle")
  end, { nargs = "?", desc = "Toggle Codex panel" })

  vim.api.nvim_create_user_command("CodexFocus", function()
    open_codex_terminal(nil, "focus")
  end, { desc = "Smart focus/unfocus Codex panel" })

  vim.api.nvim_create_user_command("CodexOpen", function()
    open_codex_terminal(nil, "open")
  end, { desc = "Open Codex panel" })

  vim.api.nvim_create_user_command("CodexClose", function()
    terminal.close()
  end, { desc = "Close Codex panel" })

  local add_handler = function()
    local file = vim.api.nvim_buf_get_name(0)
    if not file or file == "" then
      vim.notify("CodexAdd: current buffer has no file name", vim.log.levels.ERROR)
      return
    end
    M.enqueue_mention(file)
  end
  vim.api.nvim_create_user_command("CodexAdd", add_handler, { desc = "Add current buffer" })

  local visual_commands = require("codex.visual_commands")
  local send_handler = visual_commands.create_visual_command_wrapper(
      function(args)
        visual_commands.handle_send(args.line1, args.line2)
      end,
      function(line1, line2, args)
        visual_commands.handle_send(line1, line2)
      end
    )
  vim.api.nvim_create_user_command("CodexSend", send_handler, { range = true, desc = "Send selection to Codex" })

  vim.api.nvim_create_user_command("CodexDiffAccept", function()
    -- Context-aware: in diffsplit mode accepts only the current tab's file;
    -- in unified mode falls through to accept_all.
    require("codex.diff").accept_current()
  end, { desc = "Accept current Codex diff (file or all)" })

  vim.api.nvim_create_user_command("CodexDiffDeny", function()
    require("codex.diff").deny_current()
  end, { desc = "Deny current Codex diff (file or all)" })

  vim.api.nvim_create_user_command("CodexDiffAcceptAll", function()
    require("codex.diff").accept_all()
  end, { desc = "Accept all pending Codex files" })

  vim.api.nvim_create_user_command("CodexDiffDenyAll", function()
    require("codex.diff").deny_all()
  end, { desc = "Deny all pending Codex files" })

  vim.api.nvim_create_user_command("CodexSelectModel", function()
    local models = (M.state.config and M.state.config.models) or {}
    if #models == 0 then
      vim.notify("codex: no models configured — add models = {...} to setup()", vim.log.levels.WARN)
      return
    end
    local names = {}
    for _, m in ipairs(models) do
      names[#names + 1] = m.name or m.value or tostring(m)
    end
    vim.ui.select(names, { prompt = "Select Codex model:" }, function(choice, idx)
      if not choice then return end
      local model = models[idx]
      M.state.selected_model = model.value or model.name
      vim.notify("codex: model set to " .. choice, vim.log.levels.INFO)
    end)
  end, { desc = "Select Codex model" })

  vim.api.nvim_create_user_command("CodexStart", function()
    start_server()
    vim.notify("codex: starting app-server...", vim.log.levels.INFO)
  end, { desc = "Start Codex app-server" })

  vim.api.nvim_create_user_command("CodexStop", function()
    if M.state.config and M.state.config.track_selection then
      require("codex.selection").disable()
    end
    if M.state.rpc then
      M.state.rpc:close()
      M.state.rpc = nil
    end
    require("codex.app_server").stop()
    vim.notify("codex: stopped", vim.log.levels.INFO)
  end, { desc = "Stop Codex app-server" })

  vim.api.nvim_create_user_command("CodexStatus", function()
    local lines = {}
    if is_connected() then
      lines[#lines + 1] = "connected" .. (M.state.port and (" on port " .. M.state.port) or "")
    else
      lines[#lines + 1] = "not connected"
    end
    local approval = (M.state.config and M.state.config.approval) or {}
    lines[#lines + 1] = ("approval policy: %s"):format(approval.policy or "?")
    lines[#lines + 1] = ("sandbox: %s"):format(approval.sandbox or "?")
    if approval.sandbox == "workspace-write" then
      lines[#lines + 1] = "  ⚠ workspace-write means codex AUTO-APPLIES in-workspace edits"
      lines[#lines + 1] = "  ⚠ without showing the diff. Use sandbox='read-only' to require approval."
    end
    local ok_checker, checker = pcall(require, "codex.codex_config_check")
    if ok_checker then
      local home = os.getenv("HOME") or ""
      if home ~= "" then
        for _, w in ipairs(checker.warnings(checker.scan(home .. "/.codex/config.toml"))) do
          lines[#lines + 1] = "  ⚠ " .. w
        end
      end
    end
    vim.notify(
      "codex: " .. table.concat(lines, "\n  "),
      is_connected() and vim.log.levels.INFO or vim.log.levels.WARN
    )
  end, { desc = "Show Codex connection + approval status" })
end

function M.setup(opts)
  local config = require("codex.config")
  local terminal = require("codex.terminal")
  local handlers = require("codex.handlers.init")

  M.state.config = config.apply(opts or {})
  config.validate(M.state.config)

  terminal.setup(M.state.config)
  require("codex.app_server").configure(M.state.config)
  handlers.setup()
  create_commands()

  M.state.initialized = true

  -- Warn if ~/.codex/config.toml has top-level approval_policy="never" or
  -- sandbox_mode="danger-full-access" that would silently bypass the diff
  -- approval flow. Best-effort; never blocks setup.
  pcall(function()
    require("codex.codex_config_check").check_and_warn()
  end)

  if M.state.config.auto_start then
    start_server()
  end
end

return M
