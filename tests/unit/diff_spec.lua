-- tests/unit/diff_spec.lua
require("busted_setup")

describe("codex.diff", function()
  local diff

  before_each(function()
    package.loaded["codex.diff"] = nil
    diff = require("codex.diff")
  end)

  after_each(function()
    diff.state.pending = nil
  end)

  -- ── parse ──────────────────────────────────────────────────────
  describe("parse()", function()
    it("returns empty list for empty patch", function()
      assert.same({}, diff.parse(""))
    end)

    it("returns empty list for nil", function()
      assert.same({}, diff.parse(nil))
    end)

    it("parses one file with one hunk", function()
      local patch = table.concat({
        "diff --git a/file.lua b/file.lua",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,4 @@",
        " context",
        "+added",
        " context2",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals(1, #files)
      assert.equals(1, #files[1].hunks)
      assert.equals("@@ -1,3 +1,4 @@", files[1].hunks[1].header)
    end)

    it("parses two files", function()
      local patch = table.concat({
        "diff --git a/a.lua b/a.lua",
        "@@ -1,1 +1,1 @@",
        "-old",
        "+new",
        "diff --git a/b.lua b/b.lua",
        "@@ -5,1 +5,1 @@",
        "-x",
        "+y",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals(2, #files)
    end)

    it("marks binary files", function()
      local patch = table.concat({
        "diff --git a/img.png b/img.png",
        "Binary files a/img.png and b/img.png differ",
      }, "\n")
      local files = diff.parse(patch)
      assert.is_true(files[1].binary)
    end)

    it("all hunks start as accepted=true", function()
      local patch = "diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n"
      local files = diff.parse(patch)
      assert.is_true(files[1].hunks[1].accepted)
    end)

    it("parses multi-hunk file", function()
      local patch = table.concat({
        "diff --git a/file.lua b/file.lua",
        "@@ -1,2 +1,2 @@",
        "-a",
        "+b",
        "@@ -10,2 +10,2 @@",
        "-c",
        "+d",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals(2, #files[1].hunks)
    end)

    it("stores file header lines", function()
      local patch = table.concat({
        "diff --git a/a.lua b/a.lua",
        "--- a/a.lua",
        "+++ b/a.lua",
        "@@ -1,1 +1,1 @@",
        "-a",
        "+b",
      }, "\n")
      local files = diff.parse(patch)
      assert.is_truthy(#files[1].header >= 1)
    end)

    it("stores hunk body lines", function()
      local patch = "diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-old\n+new\n"
      local files = diff.parse(patch)
      assert.equals(2, #files[1].hunks[1].lines)
    end)
  end)

  -- ── set_accepted ──────────────────────────────────────────────
  describe("set_accepted()", function()
    local files
    before_each(function()
      files = diff.parse(table.concat({
        "diff --git a/a.lua b/a.lua",
        "@@ -1,1 +1,1 @@",
        "-a",
        "+b",
        "@@ -5,1 +5,1 @@",
        "-c",
        "+d",
      }, "\n"))
    end)

    it("returns false for invalid file_idx", function()
      assert.is_false(diff.set_accepted(files, 99, nil, false))
    end)

    it("returns false for invalid hunk_idx", function()
      assert.is_false(diff.set_accepted(files, 1, 99, false))
    end)

    it("sets all hunks when hunk_idx is nil", function()
      diff.set_accepted(files, 1, nil, false)
      assert.is_false(files[1].hunks[1].accepted)
      assert.is_false(files[1].hunks[2].accepted)
    end)

    it("sets only the specified hunk", function()
      diff.set_accepted(files, 1, 1, false)
      assert.is_false(files[1].hunks[1].accepted)
      assert.is_true(files[1].hunks[2].accepted)
    end)

    it("returns true on success", function()
      assert.is_true(diff.set_accepted(files, 1, 1, false))
    end)
  end)

  -- ── render ────────────────────────────────────────────────────
  describe("render()", function()
    local files
    before_each(function()
      files = diff.parse("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-old\n+new\n")
    end)

    it("returns empty string for empty files list", function()
      assert.equals("", diff.render({}, true))
    end)

    it("includes accepted hunk when accepted_only=true", function()
      local out = diff.render(files, true)
      assert.is_truthy(out:find("@@ -1,1 +1,1 @@", 1, true))
    end)

    it("excludes rejected hunk when accepted_only=true", function()
      diff.set_accepted(files, 1, 1, false)
      assert.equals("", diff.render(files, true))
    end)

    it("includes rejected hunk when accepted_only=false", function()
      diff.set_accepted(files, 1, 1, false)
      local out = diff.render(files, false)
      assert.is_truthy(out:find("@@ -1,1 +1,1 @@", 1, true))
    end)

    it("includes hunk body lines", function()
      local out = diff.render(files, true)
      assert.is_truthy(out:find("-old", 1, true))
      assert.is_truthy(out:find("+new", 1, true))
    end)

    it("output ends with newline", function()
      local out = diff.render(files, true)
      assert.equals("\n", out:sub(-1))
    end)
  end)

  -- ── has_pending / get_pending ─────────────────────────────────
  describe("has_pending() / get_pending()", function()
    it("is false initially", function()
      assert.is_false(diff.has_pending())
    end)

    it("get_pending returns nil initially", function()
      assert.is_nil(diff.get_pending())
    end)

    it("is true after open()", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      assert.is_true(diff.has_pending())
    end)
  end)

  -- ── open ──────────────────────────────────────────────────────
  describe("open()", function()
    it("sets pending.files from parsed patch", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      assert.equals(1, #diff.get_pending().files)
    end)

    it("stores respond_fn in pending", function()
      local fn = function() end
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", fn, {})
      assert.equals(fn, diff.get_pending().respond_fn)
    end)

    it("calls respond_fn immediately and clears for empty patch", function()
      local called = false
      diff.open("", function() called = true end, {})
      assert.is_true(called)
      assert.is_false(diff.has_pending())
    end)

    it("replaces an existing pending session", function()
      local fn1, fn2 = function() end, function() end
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", fn1, {})
      diff.open("diff --git a/b.lua b/b.lua\n@@ -1,1 +1,1 @@\n-c\n+d\n", fn2, {})
      assert.equals(fn2, diff.get_pending().respond_fn)
    end)

    it("silently drops old respond_fn when replacing session", function()
      local fn1_called = false
      local fn1 = function() fn1_called = true end
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", fn1, {})
      diff.open("diff --git a/b.lua b/b.lua\n@@ -1,1 +1,1 @@\n-c\n+d\n", nil, {})
      assert.is_false(fn1_called)
    end)
  end)

  -- ── accept_all ────────────────────────────────────────────────
  describe("accept_all()", function()
    it("is safe when no pending", function()
      assert.has_no.errors(function() diff.accept_all() end)
    end)

    it("calls respond_fn with accepted=true", function()
      local result = nil
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n",
        function(r) result = r end, {})
      diff.accept_all()
      assert.is_not_nil(result)
      assert.is_true(result.accepted)
    end)

    it("clears pending state", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      diff.accept_all()
      assert.is_false(diff.has_pending())
    end)

    it("includes rendered patch in respond_fn result", function()
      local result = nil
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n",
        function(r) result = r end, {})
      diff.accept_all()
      assert.is_truthy(result.patch)
      assert.is_truthy(result.patch:find("@@ -1,1 +1,1 @@", 1, true))
    end)

    it("is safe when respond_fn is nil", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      assert.has_no.errors(function() diff.accept_all() end)
    end)
  end)

  -- ── deny_all ──────────────────────────────────────────────────
  describe("deny_all()", function()
    it("is safe when no pending", function()
      assert.has_no.errors(function() diff.deny_all() end)
    end)

    it("calls respond_fn with accepted=false", function()
      local result = nil
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n",
        function(r) result = r end, {})
      diff.deny_all()
      assert.is_false(result.accepted)
    end)

    it("clears pending state", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      diff.deny_all()
      assert.is_false(diff.has_pending())
    end)
  end)

  -- ── accept_hunk / reject_hunk ─────────────────────────────────
  describe("accept_hunk() / reject_hunk()", function()
    it("accept_hunk sets hunk accepted=true", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      diff.reject_hunk(1, 1)
      diff.accept_hunk(1, 1)
      assert.is_true(diff.get_pending().files[1].hunks[1].accepted)
    end)

    it("reject_hunk sets hunk accepted=false", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      diff.reject_hunk(1, 1)
      assert.is_false(diff.get_pending().files[1].hunks[1].accepted)
    end)

    it("accept_hunk is safe when no pending", function()
      assert.has_no.errors(function() diff.accept_hunk(1, 1) end)
    end)

    it("reject_hunk is safe when no pending", function()
      assert.has_no.errors(function() diff.reject_hunk(1, 1) end)
    end)
  end)

  -- ── UI functions ───────────────────────────────────────────────
  describe("UI functions", function()
    before_each(function()
      -- nvim_win_set_cursor not in mock — add stub
      _G.vim.api.nvim_win_set_cursor = function(win, pos)
        if _G.vim._windows[win] then
          _G.vim._windows[win].cursor = pos
        end
      end
    end)

    describe("open() creates UI", function()
      it("creates a buffer", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        assert.is_not_nil(p.buf)
        assert.is_true(vim.api.nvim_buf_is_valid(p.buf))
      end)

      it("creates a window", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        assert.is_not_nil(p.win)
        assert.is_true(vim.api.nvim_win_is_valid(p.win))
      end)

      it("sets filetype=diff on buffer", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        assert.equals("diff", vim.api.nvim_buf_get_option(p.buf, "filetype"))
      end)

      it("sets buftype=nofile on buffer", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        assert.equals("nofile", vim.api.nvim_buf_get_option(p.buf, "buftype"))
      end)
    end)

    describe("_refresh_buf()", function()
      it("writes hunk header line to buffer", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-old\n+new\n", nil, {})
        local p = diff.get_pending()
        local lines = vim.api.nvim_buf_get_lines(p.buf, 0, -1, false)
        local found = false
        for _, line in ipairs(lines) do
          if line:find("@@ -1,1 +1,1 @@", 1, true) then found = true end
        end
        assert.is_true(found)
      end)

      it("marks accepted hunk with [ACCEPT]", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        local lines = vim.api.nvim_buf_get_lines(p.buf, 0, -1, false)
        local found = false
        for _, line in ipairs(lines) do
          if line:find("[ACCEPT]", 1, true) then found = true end
        end
        assert.is_true(found)
      end)

      it("marks rejected hunk with [REJECT] after reject_hunk()", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        diff.reject_hunk(1, 1)
        local p = diff.get_pending()
        local lines = vim.api.nvim_buf_get_lines(p.buf, 0, -1, false)
        local found = false
        for _, line in ipairs(lines) do
          if line:find("[REJECT]", 1, true) then found = true end
        end
        assert.is_true(found)
      end)

      it("populates hunk_map with entries", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        local has_entry = false
        for lnum, entry in pairs(p.hunk_map) do
          has_entry = true
          assert.equals(1, entry.file_idx)
          assert.equals(1, entry.hunk_idx)
        end
        assert.is_true(has_entry)
      end)

      it("populates hunk_starts list", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        assert.equals(1, #p.hunk_starts)
      end)

      it("records two hunk_starts for two hunks", function()
        local patch = table.concat({
          "diff --git a/a.lua b/a.lua",
          "@@ -1,1 +1,1 @@",
          "-a",
          "+b",
          "@@ -5,1 +5,1 @@",
          "-c",
          "+d",
        }, "\n")
        diff.open(patch, nil, {})
        assert.equals(2, #diff.get_pending().hunk_starts)
      end)
    end)

    describe("_accept_hunk_at_cursor()", function()
      it("accepts the hunk under the cursor", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        diff.reject_hunk(1, 1)
        -- place cursor on first hunk line
        local hunk_line = p.hunk_starts[1]
        vim.api.nvim_win_set_cursor(p.win, { hunk_line, 0 })
        diff._accept_hunk_at_cursor()
        assert.is_true(p.files[1].hunks[1].accepted)
      end)
    end)

    describe("_reject_hunk_at_cursor()", function()
      it("rejects the hunk under the cursor", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        local hunk_line = p.hunk_starts[1]
        vim.api.nvim_win_set_cursor(p.win, { hunk_line, 0 })
        diff._reject_hunk_at_cursor()
        assert.is_false(p.files[1].hunks[1].accepted)
      end)
    end)

    describe("_find_edit_window()", function()
      it("returns a valid window", function()
        local win = diff._find_edit_window()
        assert.is_true(vim.api.nvim_win_is_valid(win))
      end)

      it("skips terminal buftype windows", function()
        local term_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(term_buf, "buftype", "terminal")
        local term_win = vim._next_winid
        vim._next_winid = vim._next_winid + 1
        vim._windows[term_win] = { buf = term_buf, width = 80 }
        vim._win_tab[term_win] = 1
        table.insert(vim._tab_windows[1], term_win)
        vim._current_window = term_win

        local win = diff._find_edit_window()
        assert.not_equals(term_win, win)
      end)

      it("skips floating windows", function()
        local float_buf = vim.api.nvim_create_buf(false, true)
        local float_win = vim._next_winid
        vim._next_winid = vim._next_winid + 1
        vim._windows[float_win] = { buf = float_buf, width = 80, config = { relative = "editor" } }
        vim._win_tab[float_win] = 1
        table.insert(vim._tab_windows[1], float_win)
        vim._current_window = float_win

        local win = diff._find_edit_window()
        assert.not_equals(float_win, win)
      end)
    end)

    describe("_close_windows()", function()
      it("closes the diff window after open()", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        local win = p.win
        diff._close_windows()
        assert.is_false(vim.api.nvim_win_is_valid(win))
      end)

      it("is safe when buf and win are nil", function()
        diff.state.pending = { files = {}, respond_fn = nil, buf = nil, win = nil }
        assert.has_no.errors(function() diff._close_windows() end)
        diff.state.pending = nil
      end)
    end)

    describe("navigation", function()
      it("_goto_next_hunk moves cursor forward to second hunk", function()
        local patch = table.concat({
          "diff --git a/a.lua b/a.lua",
          "@@ -1,1 +1,1 @@",
          "-a",
          "+b",
          "@@ -5,1 +5,1 @@",
          "-c",
          "+d",
        }, "\n")
        diff.open(patch, nil, {})
        local p = diff.get_pending()
        local starts = p.hunk_starts
        vim.api.nvim_win_set_cursor(p.win, { starts[1], 0 })
        diff._goto_next_hunk()
        local cursor = vim.api.nvim_win_get_cursor(p.win)
        assert.equals(starts[2], cursor[1])
      end)

      it("_goto_prev_hunk moves cursor back to first hunk", function()
        local patch = table.concat({
          "diff --git a/a.lua b/a.lua",
          "@@ -1,1 +1,1 @@",
          "-a",
          "+b",
          "@@ -5,1 +5,1 @@",
          "-c",
          "+d",
        }, "\n")
        diff.open(patch, nil, {})
        local p = diff.get_pending()
        local starts = p.hunk_starts
        vim.api.nvim_win_set_cursor(p.win, { starts[2], 0 })
        diff._goto_prev_hunk()
        local cursor = vim.api.nvim_win_get_cursor(p.win)
        assert.equals(starts[1], cursor[1])
      end)
    end)

    describe("keymaps", function()
      it("sets 'A' keymap on diff buffer", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        assert.is_not_nil(vim._keymaps and vim._keymaps["n"] and vim._keymaps["n"]["A"])
      end)

      it("sets 'R' keymap on diff buffer", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        assert.is_not_nil(vim._keymaps["n"]["R"])
      end)

      it("'A' keymap calls accept_all", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local accepted = false
        -- override accept_all to track call
        local orig = diff.accept_all
        diff.accept_all = function() accepted = true end
        vim._keymaps["n"]["A"].rhs()
        diff.accept_all = orig
        assert.is_true(accepted)
      end)
    end)
  end)
end)
