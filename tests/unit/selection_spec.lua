require("busted_setup")

describe("codex.selection", function()
  local selection

  before_each(function()
    package.loaded["codex.selection"] = nil
    package.loaded["codex.terminal"] = nil

    -- stub codex.terminal
    package.preload["codex.terminal"] = function()
      return { get_active_terminal_bufnr = function() return nil end }
    end

    -- stubs for vim APIs not in mock
    _G.vim.schedule_wrap = function(fn) return fn end
    _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
    _G.vim.fn.visualmode = function() return "" end
    _G.vim.deepcopy = function(t)
      local c = {}
      for k, v in pairs(t) do c[k] = v end
      return c
    end

    selection = require("codex.selection")
  end)

  after_each(function()
    package.preload["codex.terminal"] = nil
    if selection.state.tracking_enabled then
      selection.disable()
    end
  end)

  -- ── has_selection_changed ──────────────────────────────────────────
  describe("has_selection_changed()", function()
    local function make_sel(file, text, sl, sc, el, ec)
      return {
        filePath = file,
        text = text,
        selection = {
          start = { line = sl, character = sc },
          ["end"] = { line = el, character = ec },
          isEmpty = (text == ""),
        },
      }
    end

    it("returns true when latest_selection is nil", function()
      selection.state.latest_selection = nil
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","",0,0,0,0)))
    end)

    it("returns false when selection is identical", function()
      local s = make_sel("/a.lua","hi",0,0,0,2)
      selection.state.latest_selection = s
      assert.is_false(selection.has_selection_changed(s))
    end)

    it("returns true when filePath differs", function()
      selection.state.latest_selection = make_sel("/a.lua","",0,0,0,0)
      assert.is_true(selection.has_selection_changed(make_sel("/b.lua","",0,0,0,0)))
    end)

    it("returns true when text differs", function()
      selection.state.latest_selection = make_sel("/a.lua","old",0,0,0,3)
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","new",0,0,0,3)))
    end)

    it("returns true when start.line differs", function()
      selection.state.latest_selection = make_sel("/a.lua","",0,0,0,0)
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","",1,0,1,0)))
    end)

    it("returns true when end.character differs", function()
      selection.state.latest_selection = make_sel("/a.lua","hi",0,0,0,2)
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","hi",0,0,0,5)))
    end)
  end)

  -- ── get_cursor_position ───────────────────────────────────────────
  describe("get_cursor_position()", function()
    before_each(function()
      _G.vim.api.nvim_win_get_cursor = function() return { 5, 3 } end
      _G.vim.api.nvim_buf_get_name = function() return "/path/to/file.lua" end
    end)

    it("returns isEmpty = true", function()
      assert.is_true(selection.get_cursor_position().selection.isEmpty)
    end)

    it("converts 1-indexed row to 0-indexed line", function()
      local pos = selection.get_cursor_position()
      assert.equals(4, pos.selection.start.line)  -- row 5 → line 4
    end)

    it("passes column through unchanged", function()
      local pos = selection.get_cursor_position()
      assert.equals(3, pos.selection.start.character)
    end)

    it("sets fileUrl with file:// prefix", function()
      local pos = selection.get_cursor_position()
      assert.equals("file:///path/to/file.lua", pos.fileUrl)
    end)

    it("start and end are the same point", function()
      local pos = selection.get_cursor_position()
      assert.same(pos.selection.start, pos.selection["end"])
    end)
  end)

  -- ── get_range_selection ──────────────────────────────────────────
  describe("get_range_selection()", function()
    before_each(function()
      _G.vim.api.nvim_buf_get_name = function() return "/test.lua" end
      _G.vim.api.nvim_buf_line_count = function() return 100 end
      _G.vim.api.nvim_buf_get_lines = function(_, s, e, _)
        local lines = {}
        for i = s + 1, e do
          table.insert(lines, "line_" .. i)
        end
        return lines
      end
    end)

    it("returns nil when line1 > line2", function()
      assert.is_nil(selection.get_range_selection(5, 3))
    end)

    it("returns nil when line1 < 1", function()
      assert.is_nil(selection.get_range_selection(0, 5))
    end)

    it("returns 0-indexed start line", function()
      local sel = selection.get_range_selection(3, 5)
      assert.equals(2, sel.selection.start.line)  -- 3-1
    end)

    it("returns 0-indexed end line", function()
      local sel = selection.get_range_selection(3, 5)
      assert.equals(4, sel.selection["end"].line)  -- 5-1
    end)

    it("sets filePath and fileUrl", function()
      local sel = selection.get_range_selection(1, 2)
      assert.equals("/test.lua", sel.filePath)
      assert.equals("file:///test.lua", sel.fileUrl)
    end)

    it("isEmpty = false for non-empty range", function()
      local sel = selection.get_range_selection(1, 3)
      assert.is_false(sel.selection.isEmpty)
    end)

    it("handles single-line range", function()
      local sel = selection.get_range_selection(4, 4)
      assert.equals(3, sel.selection.start.line)
      assert.equals(3, sel.selection["end"].line)
    end)
  end)

  -- ── enable / disable ────────────────────────────────────────────
  describe("enable() / disable()", function()
    local fake_rpc

    before_each(function()
      fake_rpc = { notify = function() end }
    end)

    it("sets tracking_enabled = true", function()
      selection.enable(fake_rpc, 50)
      assert.is_true(selection.state.tracking_enabled)
    end)

    it("stores rpc reference", function()
      selection.enable(fake_rpc, 50)
      assert.equals(fake_rpc, selection.rpc)
    end)

    it("is idempotent — second enable is a no-op", function()
      selection.enable(fake_rpc, 50)
      local rpc2 = { notify = function() end }
      selection.enable(rpc2, 50)
      assert.equals(fake_rpc, selection.rpc)  -- first rpc unchanged
    end)

    it("sets tracking_enabled = false after disable", function()
      selection.enable(fake_rpc, 50)
      selection.disable()
      assert.is_false(selection.state.tracking_enabled)
    end)

    it("clears rpc after disable", function()
      selection.enable(fake_rpc, 50)
      selection.disable()
      assert.is_nil(selection.rpc)
    end)

    it("clears latest_selection after disable", function()
      selection.enable(fake_rpc, 50)
      selection.state.latest_selection = { filePath = "/a.lua" }
      selection.disable()
      assert.is_nil(selection.state.latest_selection)
    end)
  end)

  -- ── send_selection_update ────────────────────────────────────────
  describe("send_selection_update()", function()
    it("calls rpc:notify with correct method and payload", function()
      local calls = {}
      selection.rpc = {
        notify = function(self, method, params)
          table.insert(calls, { method = method, params = params })
        end,
      }
      local sel = { filePath = "/a.lua", text = "hi",
        selection = { start={line=0,character=0}, ["end"]={line=0,character=2}, isEmpty=false } }
      selection.send_selection_update(sel)
      assert.equals(1, #calls)
      assert.equals("$/codex/selectionChanged", calls[1].method)
      assert.equals(sel, calls[1].params)
    end)

    it("is safe when rpc is nil", function()
      selection.rpc = nil
      assert.has_no.errors(function()
        selection.send_selection_update({ filePath = "/a.lua" })
      end)
    end)
  end)

  -- ── debounce_update ──────────────────────────────────────────────
  describe("debounce_update()", function()
    it("calls update_selection after timer fires", function()
      local update_called = false
      local original_update = selection.update_selection
      selection.update_selection = function() update_called = true end

      -- Override timer to fire callback immediately
      local orig_timer = _G.vim.loop.new_timer
      _G.vim.loop.new_timer = function()
        return {
          start = function(self, _, _, cb) cb() end,
          stop  = function(self) end,
          close = function(self) end,
        }
      end
      _G.vim.uv.new_timer = _G.vim.loop.new_timer

      selection.state.tracking_enabled = true
      selection.debounce_update()

      selection.update_selection = original_update
      _G.vim.loop.new_timer = orig_timer
      _G.vim.uv.new_timer = orig_timer

      assert.is_true(update_called)
    end)

    it("cancels a pending timer before creating a new one", function()
      local stop_count = 0
      local orig_timer = _G.vim.loop.new_timer
      _G.vim.loop.new_timer = function()
        return {
          start = function(self, _, _, cb) end,  -- do NOT fire
          stop  = function(self) stop_count = stop_count + 1 end,
          close = function(self) end,
        }
      end
      _G.vim.uv.new_timer = _G.vim.loop.new_timer

      -- First call — installs a timer
      selection.debounce_update()
      -- Second call — should cancel the first timer then create another
      selection.debounce_update()

      _G.vim.loop.new_timer = orig_timer
      _G.vim.uv.new_timer = orig_timer

      assert.is_true(stop_count >= 1, "first timer should have been stopped")
    end)
  end)
end)
