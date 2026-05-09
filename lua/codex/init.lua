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

local function build_codex_cmd(flag)
  local base = (M.state.config and M.state.config.codex_cmd) or "codex"
  local url = require("codex.app_server").url()
  if not url then return nil end
  local remote = " --remote " .. url
  if flag == "--resume" or flag == "--continue" then
    return base .. remote .. " resume --last"
  end
  return base .. remote
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
    local url = require("codex.app_server").url()
    if not url then
      vim.notify("codex: app-server not ready — cannot open terminal for mention", vim.log.levels.WARN)
      return
    end
    local base = (M.state.config and M.state.config.codex_cmd) or "codex"
    terminal.open(base .. " --remote " .. url)
    vim.defer_fn(send_all, 1500)
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

  vim.api.nvim_create_user_command("Codex", function(args)
    local arg = (args.args or ""):match("^%s*(.-)%s*$")
    if terminal.get_active_terminal_bufnr() then
      terminal.simple_toggle()
      return
    end
    local app_server = require("codex.app_server")
    app_server.ensure(function(_, err)
      if err then
        vim.notify("codex: app-server not ready — " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      vim.schedule(function()
        terminal.open(build_codex_cmd(arg))
      end)
    end)
  end, { nargs = "?", desc = "Toggle Codex panel" })

  vim.api.nvim_create_user_command("CodexFocus", function()
    terminal.focus_toggle()
  end, { desc = "Smart focus/unfocus Codex panel" })

  vim.api.nvim_create_user_command("CodexOpen", function()
    terminal.open()
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
    require("codex.diff").accept_all()
  end, { desc = "Accept pending Codex diff" })

  vim.api.nvim_create_user_command("CodexDiffDeny", function()
    require("codex.diff").deny_all()
  end, { desc = "Deny pending Codex diff" })

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
    if is_connected() then
      vim.notify(
        "codex: connected" .. (M.state.port and " on port " .. M.state.port or ""),
        vim.log.levels.INFO
      )
    else
      vim.notify("codex: not connected", vim.log.levels.WARN)
    end
  end, { desc = "Show Codex connection status" })
end

function M.setup(opts)
  local config = require("codex.config")
  local terminal = require("codex.terminal")

  M.state.config = config.apply(opts or {})
  config.validate(M.state.config)

  terminal.setup(M.state.config)
  require("codex.app_server").configure(M.state.config)
  create_commands()

  M.state.initialized = true

  if M.state.config.auto_start then
    start_server()
  end
end

return M
