require("busted_setup")

describe("codex.terminal.snacks", function()
  local snacks_mod

  local function reload()
    package.loaded["codex.terminal.snacks"] = nil
    return require("codex.terminal.snacks")
  end

  describe("without snacks.nvim", function()
    before_each(function()
      package.loaded["snacks"] = nil
      package.preload["snacks"] = function() error("snacks not installed") end
      snacks_mod = reload()
    end)
    after_each(function()
      package.preload["snacks"] = nil
    end)

    it("is_available() returns false", function()
      assert.is_false(snacks_mod.is_available())
    end)
    it("open() does nothing and does not error", function()
      assert.has_no.errors(function() snacks_mod.open("codex", {}) end)
    end)
    it("get_active_bufnr() returns nil", function()
      assert.is_nil(snacks_mod.get_active_bufnr())
    end)
    it("close() does not error", function()
      assert.has_no.errors(function() snacks_mod.close() end)
    end)
    it("focus_toggle() does not error", function()
      assert.has_no.errors(function() snacks_mod.focus_toggle("codex", {}) end)
    end)
  end)

  describe("with snacks mock", function()
    local fake_terminal_instance
    local toggle_calls

    before_each(function()
      toggle_calls = {}
      fake_terminal_instance = {
        buf = 77,
        win = 88,
        is_hidden = function() return false end,
        hide = function() end,
        close = function() fake_terminal_instance.buf = nil end,
      }
      local fake_snacks = {
        terminal = {
          toggle = function(cmd, _opts)
            table.insert(toggle_calls, cmd)
            return fake_terminal_instance
          end,
        },
      }
      package.loaded["snacks"] = fake_snacks
      package.preload["snacks"] = nil
      snacks_mod = reload()
      -- Set up buffer 77 in the vim mock so it's valid
      vim._mock.add_buffer(77, "snacks terminal", "")
    end)
    after_each(function()
      package.loaded["snacks"] = nil
      vim._mock.reset()
    end)

    it("is_available() returns true", function()
      assert.is_true(snacks_mod.is_available())
    end)
    it("open() calls snacks.terminal.toggle with the command", function()
      snacks_mod.open("codex", {})
      assert.equals(1, #toggle_calls)
      assert.equals("codex", toggle_calls[1])
    end)
    it("get_active_bufnr() returns terminal buf after open()", function()
      snacks_mod.open("codex", {})
      assert.equals(77, snacks_mod.get_active_bufnr())
    end)
    it("get_active_bufnr() returns nil before open()", function()
      assert.is_nil(snacks_mod.get_active_bufnr())
    end)
    it("simple_toggle() calls snacks.terminal.toggle", function()
      snacks_mod.simple_toggle("codex", {})
      assert.equals(1, #toggle_calls)
    end)
    it("_get_terminal_for_test() returns the stored terminal", function()
      snacks_mod.open("codex", {})
      assert.equals(fake_terminal_instance, snacks_mod._get_terminal_for_test())
    end)

    describe("focus_toggle()", function()
      it("calls toggle when no terminal is open", function()
        snacks_mod.focus_toggle("codex", {})
        assert.equals(1, #toggle_calls)
      end)

      it("hides terminal when current window is the terminal", function()
        local hidden = false
        fake_terminal_instance.hide = function() hidden = true end
        fake_terminal_instance.is_hidden = function() return false end
        -- register win 88 so nvim_win_is_valid returns true
        vim._mock.add_window(fake_terminal_instance.win, 77)
        -- open first so terminal is tracked
        snacks_mod.open("codex", {})
        -- make current window = terminal window
        _G.vim._current_window = fake_terminal_instance.win
        toggle_calls = {}  -- reset
        snacks_mod.focus_toggle("codex", {})
        assert.is_true(hidden)
      end)

      it("focuses terminal when visible but not the current window", function()
        local focused_win = nil
        local original_set = _G.vim.api.nvim_set_current_win
        _G.vim.api.nvim_set_current_win = function(w) focused_win = w; original_set(w) end
        fake_terminal_instance.is_hidden = function() return false end
        -- register win 88 so nvim_win_is_valid returns true
        vim._mock.add_window(fake_terminal_instance.win, 77)
        snacks_mod.open("codex", {})
        _G.vim._current_window = 9999  -- different window
        toggle_calls = {}
        snacks_mod.focus_toggle("codex", {})
        _G.vim.api.nvim_set_current_win = original_set
        assert.equals(fake_terminal_instance.win, focused_win)
      end)
    end)
  end)
end)
