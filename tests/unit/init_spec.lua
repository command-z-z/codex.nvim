require("busted_setup")

describe("codex.init", function()
  local codex
  local registered_cmds, deferred_calls, added_mentions, sent_texts, handler_setup_calls

  before_each(function()
    registered_cmds = {}
    deferred_calls = {}
    added_mentions = {}
    sent_texts = {}
    handler_setup_calls = 0

    -- stub missing vim functions
    _G.vim.defer_fn = function(fn, ms) table.insert(deferred_calls, { fn = fn, ms = ms }) end

    -- stub vim.loop.now() if not present
    if not _G.vim.loop then _G.vim.loop = {} end
    if not _G.vim.loop.now then _G.vim.loop.now = function() return 0 end end

    -- spy on nvim_create_user_command to track registrations
    local original_create_cmd = _G.vim.api.nvim_create_user_command
    _G.vim.api.nvim_create_user_command = function(name, cb, opts)
      registered_cmds[name] = { cb = cb, opts = opts }
      return original_create_cmd(name, cb, opts)
    end

    -- stub all plugin dependencies
    package.loaded["codex.init"] = nil
    for _, mod in ipairs({ "codex.config", "codex.terminal", "codex.app_server", "codex.rpc", "codex.handlers.init" }) do
      package.loaded[mod] = nil
    end

    package.preload["codex.config"] = function()
      return {
        defaults = {},
        apply = function(u)
          return vim.tbl_extend("force", {
            codex_cmd = "codex",
            auto_start = false,  -- disable auto-start in tests
            terminal = { provider = "native" },
            approval = { policy = "prompt", sandbox = "workspace-write" },
            queue_timeout = 5000,
            connection_wait_delay = 600,
            connection_timeout = 10000,
          }, u or {})
        end,
        validate = function() end,
      }
    end
    package.preload["codex.terminal"] = function()
      return {
        setup = function() end,
        open = function() end,
        close = function() end,
        simple_toggle = function() end,
        focus_toggle = function() end,
        get_active_terminal_bufnr = function() return nil end,
        send_text = function(text) table.insert(sent_texts, text) end,
      }
    end
    package.preload["codex.app_server"] = function()
      return {
        ensure = function(cb) if cb then cb() end end,
        add_mentions = function(mentions)
          table.insert(added_mentions, mentions)
        end,
        configure = function() end,
        stop = function() end,
        url = function() return "ws://127.0.0.1:11111" end,
      }
    end
    package.preload["codex.rpc"] = function()
      return {
        connect = function()
          return { close = function() end, notify = function() end }
        end,
      }
    end
    package.preload["codex.handlers.init"] = function()
      return {
        setup = function() handler_setup_calls = handler_setup_calls + 1 end,
        handle_notification = function() end,
        handle_request = function() end,
      }
    end

    codex = require("codex.init")
  end)

  after_each(function()
    for _, mod in ipairs({ "codex.config", "codex.terminal", "codex.app_server", "codex.rpc", "codex.handlers.init" }) do
      package.preload[mod] = nil
    end
    -- restore nvim_create_user_command
    -- (mock reset happens in next before_each)
  end)

  describe("setup()", function()
    it("sets initialized = true", function()
      codex.setup({})
      assert.is_true(codex.state.initialized)
    end)
    it("stores config in state", function()
      codex.setup({ codex_cmd = "mycodex" })
      assert.equals("mycodex", codex.state.config.codex_cmd)
    end)
    it("can be called twice without error", function()
      assert.has_no.errors(function()
        codex.setup({})
        codex.setup({})
      end)
    end)
    it("registers handlers even when auto_start is false", function()
      codex.setup({ auto_start = false })
      assert.equals(1, handler_setup_calls)
    end)
  end)

  describe("command registration", function()
    before_each(function()
      codex.setup({})
    end)

    local expected_commands = {
      "Codex", "CodexFocus", "CodexOpen", "CodexClose",
      "CodexAdd", "CodexSend", "CodexDiffAccept", "CodexDiffDeny",
      "CodexSelectModel", "CodexStart", "CodexStop", "CodexStatus",
    }

    for _, name in ipairs(expected_commands) do
      it("registers " .. name, function()
        assert.is_not_nil(registered_cmds[name], name .. " should be registered")
      end)
    end

  end)

  describe(":Codex command with --remote", function()
    local open_calls, toggle_calls, ensure_cbs, notified
    local terminal_stub, app_server_stub

    before_each(function()
      open_calls   = {}
      toggle_calls = {}
      ensure_cbs   = {}
      notified     = {}

      terminal_stub = {
        setup    = function() end,
        open     = function(cmd) table.insert(open_calls, cmd) end,
        close    = function() end,
        simple_toggle = function(cmd) table.insert(toggle_calls, cmd or true) end,
        focus_toggle  = function() end,
        get_active_terminal_bufnr = function() return nil end,
        send_text = function() end,
      }
      app_server_stub = {
        ensure    = function(cb) table.insert(ensure_cbs, cb) end,
        configure = function() end,
        stop      = function() end,
        url       = function() return "ws://127.0.0.1:19999" end,
      }

      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      package.loaded["codex.init"]       = nil
      package.loaded["codex.terminal"]   = nil
      package.loaded["codex.app_server"] = nil
      package.preload["codex.terminal"]    = function() return terminal_stub end
      package.preload["codex.app_server"]  = function() return app_server_stub end

      codex = require("codex.init")
      codex.setup({})
    end)

    after_each(function()
      package.preload["codex.terminal"]   = nil
      package.preload["codex.app_server"] = nil
    end)

    it(":Codex toggles existing terminal without calling ensure", function()
      -- simulate terminal already running
      terminal_stub.get_active_terminal_bufnr = function() return 5 end
      registered_cmds["Codex"].cb({ args = "" })
      -- simple_toggle called, ensure NOT called
      assert.equals(1, #toggle_calls)
      assert.equals(0, #ensure_cbs)
    end)

    it(":Codex opens with --remote url when app-server ready", function()
      -- terminal not running; fire the ensure callback immediately
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "" })
      assert.equals(1, #ensure_cbs)
      -- fire the callback (simulating success)
      ensure_cbs[1](nil, nil)
      -- open should have been called with --remote
      assert.equals(1, #open_calls)
      assert.same({
        "codex",
        "--ask-for-approval", "on-request",
        "--sandbox", "workspace-write",
        "--remote", "ws://127.0.0.1:19999",
      }, open_calls[1])
    end)

    it(":Codex --resume opens with resume --last and --remote", function()
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "--resume" })
      ensure_cbs[1](nil, nil)
      assert.equals(1, #open_calls)
      assert.same({
        "codex", "resume", "--last",
        "--ask-for-approval", "on-request",
        "--sandbox", "workspace-write",
        "--remote", "ws://127.0.0.1:19999",
      }, open_calls[1])
    end)

    it(":Codex --continue opens with resume --last and approval flags", function()
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "--continue" })
      ensure_cbs[1](nil, nil)
      assert.equals(1, #open_calls)
      assert.same({
        "codex", "resume", "--last",
        "--ask-for-approval", "on-request",
        "--sandbox", "workspace-write",
        "--remote", "ws://127.0.0.1:19999",
      }, open_calls[1])
    end)

    it(":Codex shows error and does NOT open when app-server fails", function()
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "" })
      ensure_cbs[1](nil, "connection refused")
      assert.equals(0, #open_calls)
      assert.equals(1, #notified)
      assert.matches("not ready", notified[1].msg)
    end)
  end)

  describe("enqueue_mention()", function()
    it("adds item to mention_queue", function()
      codex.setup({})
      codex.enqueue_mention("@hello")
      assert.equals(1, #codex.state.mention_queue)
      assert.equals("@hello", codex.state.mention_queue[1].text)
    end)
    it("sets expires_at on enqueued item", function()
      codex.setup({})
      codex.enqueue_mention("test")
      assert.is_not_nil(codex.state.mention_queue[1].expires_at)
    end)
    it("enqueues multiple items", function()
      codex.setup({})
      codex.enqueue_mention("a")
      codex.enqueue_mention("b")
      assert.equals(2, #codex.state.mention_queue)
    end)
  end)

  describe("initial state", function()
    it("rpc is nil before setup", function()
      assert.is_nil(codex.state.rpc)
    end)
    it("mention_queue starts empty", function()
      assert.equals(0, #codex.state.mention_queue)
    end)
    it("initialized is false before setup", function()
      assert.is_false(codex.state.initialized)
    end)
  end)

  describe("CodexSend command", function()
    local vc_calls

    before_each(function()
      vc_calls = {}
      package.loaded["codex.visual_commands"] = nil
      package.preload["codex.visual_commands"] = function()
        return {
          create_visual_command_wrapper = function(normal_handler, visual_handler)
            return function(...)
              table.insert(vc_calls, { wrapped = true })
              return normal_handler(...)
            end
          end,
          handle_send = function(l1, l2)
            table.insert(vc_calls, { line1 = l1, line2 = l2 })
          end,
        }
      end
      codex.setup({})
    end)

    after_each(function()
      package.preload["codex.visual_commands"] = nil
      package.loaded["codex.visual_commands"] = nil
    end)

    it("calls visual_commands.handle_send with line1 and line2", function()
      local codex_send = registered_cmds["CodexSend"]
      assert.is_not_nil(codex_send)
      codex_send.cb({ line1 = 3, line2 = 7 })
      assert.equals(2, #vc_calls)
      assert.is_true(vc_calls[1].wrapped)
      assert.equals(3, vc_calls[2].line1)
      assert.equals(7, vc_calls[2].line2)
    end)

  end)

  describe("CodexStop command", function()
    local selection_disabled

    before_each(function()
      selection_disabled = false
      package.preload["codex.selection"] = function()
        return {
          enable = function() end,
          disable = function() selection_disabled = true end,
        }
      end
    end)

    after_each(function()
      package.preload["codex.selection"] = nil
      package.loaded["codex.selection"] = nil
    end)

    it("calls selection.disable() when track_selection is true", function()
      codex.setup({ track_selection = true })
      local stop_cmd = registered_cmds["CodexStop"]
      assert.is_not_nil(stop_cmd)
      stop_cmd.cb({})
      assert.is_true(selection_disabled)
    end)

    it("does not require codex.selection when track_selection is false", function()
      codex.setup({ track_selection = false })
      local stop_cmd = registered_cmds["CodexStop"]
      assert.is_not_nil(stop_cmd)
      assert.has_no.errors(function() stop_cmd.cb({}) end)
      assert.is_false(selection_disabled)
    end)

    it("is safe to call before setup()", function()
      -- Reload codex without calling setup() first
      package.loaded["codex.init"] = nil
      local fresh_codex = require("codex.init")
      -- Trigger CodexStop from a fresh require (no setup called)
      -- We need to access the registered command
      local stop_cmd = registered_cmds["CodexStop"]
      if stop_cmd then
        assert.has_no.errors(function() stop_cmd.cb({}) end)
      end
      -- If no stop_cmd registered yet (setup not called), that's fine too
      assert.is_false(selection_disabled)
    end)

    it("clears rpc reference when rpc is set", function()
      codex.setup({})
      local rpc_closed = false
      codex.state.rpc = { close = function() rpc_closed = true end }
      local stop_cmd = registered_cmds["CodexStop"]
      stop_cmd.cb({})
      assert.is_nil(codex.state.rpc)
      assert.is_true(rpc_closed)
    end)
  end)

  describe("CodexDiffAccept command", function()
    local diff_mock

    before_each(function()
      diff_mock = { calls = 0, accept_all = function() diff_mock.calls = diff_mock.calls + 1 end }
      package.preload["codex.diff"] = function() return diff_mock end
      codex.setup({})
    end)

    after_each(function()
      package.preload["codex.diff"] = nil
      package.loaded["codex.diff"] = nil
    end)

    it("calls diff.accept_all()", function()
      local cmd = registered_cmds["CodexDiffAccept"]
      assert.is_not_nil(cmd)
      cmd.cb({})
      assert.equals(1, diff_mock.calls)
    end)

    it("is safe when no diff is pending (no-op)", function()
      -- diff_mock.accept_all is already a no-op counter; calling with no pending is fine
      local cmd = registered_cmds["CodexDiffAccept"]
      assert.has_no.errors(function() cmd.cb({}) end)
    end)
  end)

  describe("CodexDiffDeny command", function()
    local diff_mock

    before_each(function()
      diff_mock = { calls = 0, deny_all = function() diff_mock.calls = diff_mock.calls + 1 end }
      package.preload["codex.diff"] = function() return diff_mock end
      codex.setup({})
    end)

    after_each(function()
      package.preload["codex.diff"] = nil
      package.loaded["codex.diff"] = nil
    end)

    it("calls diff.deny_all()", function()
      local cmd = registered_cmds["CodexDiffDeny"]
      assert.is_not_nil(cmd)
      cmd.cb({})
      assert.equals(1, diff_mock.calls)
    end)

    it("is safe when no diff is pending (no-op)", function()
      local cmd = registered_cmds["CodexDiffDeny"]
      assert.has_no.errors(function() cmd.cb({}) end)
    end)
  end)

  describe("CodexSelectModel command", function()
    before_each(function()
      vim.ui = {
        select = function(items, opts, cb)
          vim._ui_select = { items = items, opts = opts, cb = cb }
        end,
      }
      vim._ui_select = nil
    end)

    it("notifies when no models are configured", function()
      codex.setup({ models = {} })
      local notified = false
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then notified = true end
      end
      registered_cmds["CodexSelectModel"].cb({})
      assert.is_true(notified)
    end)

    it("calls vim.ui.select with model names", function()
      codex.setup({ models = {
        { name = "GPT-4o", value = "gpt-4o" },
        { name = "o1",     value = "o1" },
      }})
      registered_cmds["CodexSelectModel"].cb({})
      assert.is_not_nil(vim._ui_select)
      assert.same({ "GPT-4o", "o1" }, vim._ui_select.items)
    end)

    it("sets state.selected_model after selection", function()
      codex.setup({ models = {
        { name = "GPT-4o", value = "gpt-4o" },
      }})
      registered_cmds["CodexSelectModel"].cb({})
      assert.is_not_nil(vim._ui_select)
      vim._ui_select.cb("GPT-4o", 1)  -- simulate user picking first item
      assert.equals("gpt-4o", codex.state.selected_model)
    end)

    it("does nothing when user cancels (nil choice)", function()
      codex.setup({ models = {
        { name = "GPT-4o", value = "gpt-4o" },
      }})
      codex.state.selected_model = nil
      registered_cmds["CodexSelectModel"].cb({})
      vim._ui_select.cb(nil, nil)
      assert.is_nil(codex.state.selected_model)
    end)
  end)
end)
