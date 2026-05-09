require("busted_setup")

describe("codex.visual_commands", function()
  local vc
  local mention_calls, feedkeys_calls

  before_each(function()
    package.loaded["codex.visual_commands"] = nil
    package.loaded["codex.init"] = nil

    mention_calls = {}
    feedkeys_calls = {}

    _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
    _G.vim.api.nvim_replace_termcodes = function(s, _, _, _) return s end
    _G.vim.api.nvim_feedkeys = function(keys, _, _)
      table.insert(feedkeys_calls, keys)
    end
    _G.vim.fn.getpos = function(mark)
      if mark == "v"  then return { 0, 0, 0, 0 } end
      if mark == "'<" then return { 0, 1, 1, 0 } end
      if mark == "'>" then return { 0, 1, 10, 0 } end
      return { 0, 0, 0, 0 }
    end

    package.preload["codex.init"] = function()
      return {
        enqueue_mention = function(text)
          table.insert(mention_calls, text)
        end,
      }
    end

    vc = require("codex.visual_commands")
  end)

  after_each(function()
    package.preload["codex.init"] = nil
  end)

  -- ── validate_visual_mode ─────────────────────────────────────────
  describe("validate_visual_mode()", function()
    it("returns false in normal mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      local ok, err = vc.validate_visual_mode()
      assert.is_false(ok)
      assert.is_truthy(err:find("Not in visual mode"))
    end)

    it("returns true in 'v' mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      assert.is_true(vc.validate_visual_mode())
    end)

    it("returns true in 'V' (linewise) mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "V" } end
      assert.is_true(vc.validate_visual_mode())
    end)
  end)

  -- ── get_visual_range ─────────────────────────────────────────────
  describe("get_visual_range()", function()
    it("uses cursor + anchor in visual mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 10, 0 } end
      _G.vim.fn.getpos = function(m)
        if m == "v" then return { 0, 5, 1, 0 } end
        return { 0, 0, 0, 0 }
      end
      local s, e = vc.get_visual_range()
      assert.equals(5, s)
      assert.equals(10, e)
    end)

    it("uses '<,'> marks when not in visual mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      _G.vim.fn.getpos = function(m)
        if m == "'<" then return { 0, 3, 1, 0 } end
        if m == "'>" then return { 0, 8, 1, 0 } end
        return { 0, 0, 0, 0 }
      end
      local s, e = vc.get_visual_range()
      assert.equals(3, s)
      assert.equals(8, e)
    end)

    it("returns at least 1 for both values even with zero marks", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      _G.vim.fn.getpos = function() return { 0, 0, 0, 0 } end
      local s, e = vc.get_visual_range()
      assert.is_true(s >= 1)
      assert.is_true(e >= 1)
    end)

    it("swaps start/end if reversed", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
      _G.vim.fn.getpos = function(m)
        if m == "v" then return { 0, 10, 1, 0 } end
        return { 0, 0, 0, 0 }
      end
      local s, e = vc.get_visual_range()
      assert.equals(3, s)
      assert.equals(10, e)
    end)
  end)

  -- ── handle_send ──────────────────────────────────────────────────
  describe("handle_send()", function()
    before_each(function()
      _G.vim.api.nvim_get_current_buf = function() return 1 end
      _G.vim.api.nvim_buf_get_name = function() return "/project/main.lua" end
    end)

    it("enqueues file:start-end mention for a valid range", function()
      vc.handle_send(5, 10)
      assert.equals(1, #mention_calls)
      assert.equals("/project/main.lua:5-10", mention_calls[1])
    end)

    it("enqueues just the file path when no range given", function()
      vc.handle_send(nil, nil)
      assert.equals(1, #mention_calls)
      assert.equals("/project/main.lua", mention_calls[1])
    end)

    it("enqueues single line as start-end with same line", function()
      vc.handle_send(7, 7)
      assert.equals("/project/main.lua:7-7", mention_calls[1])
    end)

    it("warns and does not enqueue when buffer has no file", function()
      _G.vim.api.nvim_buf_get_name = function() return "" end
      local warned = false
      local orig_notify = _G.vim.notify
      _G.vim.notify = function(_, lvl) if lvl == vim.log.levels.WARN then warned = true end end
      vc.handle_send(1, 5)
      _G.vim.notify = orig_notify
      assert.is_true(warned)
      assert.equals(0, #mention_calls)
    end)
  end)

  -- ── exit_visual_and_schedule ─────────────────────────────────────
  describe("exit_visual_and_schedule()", function()
    it("sends ESC key", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
      _G.vim.fn.getpos = function(m) if m == "v" then return {0,3,0,0} end; return {0,0,0,0} end
      vc.exit_visual_and_schedule(function() end)
      assert.equals(1, #feedkeys_calls)
    end)

    it("calls callback with start and end line", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 8, 0 } end
      _G.vim.fn.getpos = function(m) if m == "v" then return {0,4,0,0} end; return {0,0,0,0} end

      local cb_args = nil
      vc.exit_visual_and_schedule(function(s, e) cb_args = { s, e } end)
      assert.is_not_nil(cb_args)
      assert.equals(4, cb_args[1])  -- start
      assert.equals(8, cb_args[2])  -- end
    end)
  end)

  -- ── create_visual_command_wrapper ────────────────────────────────
  describe("create_visual_command_wrapper()", function()
    it("calls normal_handler in normal mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      local normal_called = false
      local fn = vc.create_visual_command_wrapper(
        function() normal_called = true end,
        function() end
      )
      fn()
      assert.is_true(normal_called)
    end)

    it("calls visual_handler in visual mode (via exit_visual_and_schedule)", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
      _G.vim.fn.getpos = function(m) if m == "v" then return {0,1,0,0} end; return {0,0,0,0} end

      local visual_called = false
      local fn = vc.create_visual_command_wrapper(
        function() end,
        function() visual_called = true end
      )
      fn()
      assert.is_true(visual_called)
    end)
  end)
end)
