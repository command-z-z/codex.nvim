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
}

local function is_connected()
  return M.state.rpc ~= nil
end

local function flush_mentions()
  if not is_connected() or #M.state.mention_queue == 0 then
    return
  end
  local rpc = M.state.rpc
  local now = vim.loop.now()
  local queue = {}
  for _, item in ipairs(M.state.mention_queue) do
    if item.expires_at > now then
      table.insert(queue, item)
    end
  end
  M.state.mention_queue = {}

  local function send_next(i)
    if i > #queue then return end
    rpc:notify("$/codex/mention", { text = queue[i].text })
    vim.defer_fn(function() send_next(i + 1) end, 25)
  end
  send_next(1)
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
  if is_connected() then
    schedule_flush()
  else
    vim.defer_fn(function()
      local now = vim.loop.now()
      local fresh = {}
      for _, item in ipairs(M.state.mention_queue) do
        if item.expires_at > now then
          table.insert(fresh, item)
        end
      end
      M.state.mention_queue = fresh
    end, timeout)
  end
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
  local rpc_mod = require("codex.rpc")

  app_server.ensure(function()
    local url = app_server.url()
    local rpc = rpc_mod.connect(url, {
      on_notification = function(_method, _params)
        -- Phase 4/5: handlers registered here
      end,
      on_request = function(_method, _params, _respond)
        -- Phase 5: approval handler
      end,
    })
    on_connected(rpc)
  end)
end

local function create_commands()
  local terminal = require("codex.terminal")

  vim.api.nvim_create_user_command("Codex", function(args)
    local arg = (args.args or ""):match("^%s*(.-)%s*$")
    if arg == "--resume" or arg == "--continue" then
      M.state._open_flag = arg
    else
      M.state._open_flag = nil
    end
    terminal.simple_toggle()
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

  vim.api.nvim_create_user_command("CodexAdd", function(args)
    local parts = {}
    for part in (args.args .. " "):gmatch("([^%s]+)%s*") do
      table.insert(parts, part)
    end
    local file = parts[1]
    if not file or file == "" then
      vim.notify("CodexAdd: file argument required", vim.log.levels.ERROR)
      return
    end
    local text = file
    if parts[2] then
      text = text .. ":" .. parts[2]
      if parts[3] then text = text .. "-" .. parts[3] end
    end
    M.enqueue_mention(text)
  end, { nargs = "+", complete = "file", desc = "Add file/range to Codex context" })

  vim.api.nvim_create_user_command("CodexSend", function(args)
    local visual_commands = require("codex.visual_commands")
    visual_commands.handle_send(args.line1, args.line2)
  end, { range = true, desc = "Send selection to Codex" })

  vim.api.nvim_create_user_command("CodexDiffAccept", function()
    vim.notify("CodexDiffAccept: implemented in Phase 4", vim.log.levels.INFO)
  end, { desc = "Accept pending Codex diff" })

  vim.api.nvim_create_user_command("CodexDiffDeny", function()
    vim.notify("CodexDiffDeny: implemented in Phase 4", vim.log.levels.INFO)
  end, { desc = "Deny pending Codex diff" })

  vim.api.nvim_create_user_command("CodexSelectModel", function()
    vim.notify("CodexSelectModel: implemented in Phase 6", vim.log.levels.INFO)
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
  create_commands()

  M.state.initialized = true

  if M.state.config.auto_start then
    start_server()
  end
end

return M
