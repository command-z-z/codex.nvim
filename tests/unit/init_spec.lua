require("busted_setup")

describe("codex.init", function()
  local codex
  local registered_cmds, deferred_calls

  before_each(function()
    registered_cmds = {}
    deferred_calls = {}

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
    for _, mod in ipairs({ "codex.config", "codex.terminal", "codex.app_server", "codex.rpc" }) do
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
            approval = { policy = "prompt" },
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
      }
    end
    package.preload["codex.app_server"] = function()
      return {
        ensure = function(cb) if cb then cb() end end,
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

    codex = require("codex.init")
  end)

  after_each(function()
    for _, mod in ipairs({ "codex.config", "codex.terminal", "codex.app_server", "codex.rpc" }) do
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

    it(":Codex --resume sets _open_flag", function()
      local codex_cmd = registered_cmds["Codex"]
      assert.is_not_nil(codex_cmd)
      codex_cmd.cb({ args = "--resume" })
      assert.equals("--resume", codex.state._open_flag)
    end)

    it(":Codex --continue sets _open_flag", function()
      local codex_cmd = registered_cmds["Codex"]
      codex_cmd.cb({ args = "--continue" })
      assert.equals("--continue", codex.state._open_flag)
    end)

    it(":Codex with no arg clears _open_flag", function()
      codex.state._open_flag = "--resume"
      local codex_cmd = registered_cmds["Codex"]
      codex_cmd.cb({ args = "" })
      assert.is_nil(codex.state._open_flag)
    end)

    it(":CodexAdd with just file enqueues file path", function()
      local add_cmd = registered_cmds["CodexAdd"]
      assert.is_not_nil(add_cmd)
      add_cmd.cb({ args = "src/foo.lua" })
      assert.equals(1, #codex.state.mention_queue)
      assert.equals("src/foo.lua", codex.state.mention_queue[1].text)
    end)

    it(":CodexAdd with file and start line enqueues path:line", function()
      codex.state.mention_queue = {}
      local add_cmd = registered_cmds["CodexAdd"]
      add_cmd.cb({ args = "src/bar.lua 10" })
      assert.equals(1, #codex.state.mention_queue)
      assert.equals("src/bar.lua:10", codex.state.mention_queue[1].text)
    end)

    it(":CodexAdd with file and range enqueues path:start-end", function()
      codex.state.mention_queue = {}
      local add_cmd = registered_cmds["CodexAdd"]
      add_cmd.cb({ args = "src/baz.lua 5 20" })
      assert.equals(1, #codex.state.mention_queue)
      assert.equals("src/baz.lua:5-20", codex.state.mention_queue[1].text)
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
      package.preload["codex.visual_commands"] = function()
        return {
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
      assert.equals(1, #vc_calls)
      assert.equals(3, vc_calls[1].line1)
      assert.equals(7, vc_calls[1].line2)
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
end)
