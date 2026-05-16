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

    it("all hunks start as accepted=true", function()
      local patch = "diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n"
      local files = diff.parse(patch)
      assert.is_true(files[1].hunks[1].accepted)
    end)

    -- ── Phase 7: path + kind extraction ───────────────────────────
    it("extracts path from diff --git header", function()
      local patch = "diff --git a/lua/foo.lua b/lua/foo.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n"
      local files = diff.parse(patch)
      assert.equals("lua/foo.lua", files[1].path)
    end)

    it("handles paths with subdirectories", function()
      local patch = "diff --git a/lua/codex/diff.lua b/lua/codex/diff.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n"
      local files = diff.parse(patch)
      assert.equals("lua/codex/diff.lua", files[1].path)
    end)

    it("kind defaults to 'modify' for regular changes", function()
      local patch = "diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n"
      local files = diff.parse(patch)
      assert.equals("modify", files[1].kind)
    end)

    it("kind='new' for new file mode", function()
      local patch = table.concat({
        "diff --git a/new.lua b/new.lua",
        "new file mode 100644",
        "--- /dev/null",
        "+++ b/new.lua",
        "@@ -0,0 +1,2 @@",
        "+line1",
        "+line2",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals("new", files[1].kind)
      assert.equals("new.lua", files[1].path)
    end)

    it("kind='delete' for deleted file mode", function()
      local patch = table.concat({
        "diff --git a/old.lua b/old.lua",
        "deleted file mode 100644",
        "--- a/old.lua",
        "+++ /dev/null",
        "@@ -1,2 +0,0 @@",
        "-line1",
        "-line2",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals("delete", files[1].kind)
    end)

    it("kind='binary' for binary files (also sets binary=true)", function()
      local patch = table.concat({
        "diff --git a/img.png b/img.png",
        "Binary files a/img.png and b/img.png differ",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals("binary", files[1].kind)
      assert.is_true(files[1].binary)
    end)

    it("multi-file patch records per-file kind/path", function()
      local patch = table.concat({
        "diff --git a/a.lua b/a.lua",
        "@@ -1,1 +1,1 @@",
        "-x",
        "+y",
        "diff --git a/b.lua b/b.lua",
        "new file mode 100644",
        "--- /dev/null",
        "+++ b/b.lua",
        "@@ -0,0 +1,1 @@",
        "+hi",
      }, "\n")
      local files = diff.parse(patch)
      assert.equals("a.lua",   files[1].path)
      assert.equals("modify",  files[1].kind)
      assert.equals("b.lua",   files[2].path)
      assert.equals("new",     files[2].kind)
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

    it("calls respond_fn with approved decision", function()
      local result = nil
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n",
        function(r) result = r end, {})
      diff.accept_all()
      assert.is_not_nil(result)
      assert.equals("approved", result.decision)
    end)

    it("clears pending state", function()
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
      diff.accept_all()
      assert.is_false(diff.has_pending())
    end)

    it("does not include a rendered patch in respond_fn result", function()
      local result = nil
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n",
        function(r) result = r end, {})
      diff.accept_all()
      assert.is_nil(result.patch)
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

    it("calls respond_fn with denied decision", function()
      local result = nil
      diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n",
        function(r) result = r end, {})
      diff.deny_all()
      assert.equals("denied", result.decision)
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
        local hunk_line = p.hunk_starts[1]
        vim.api.nvim_win_set_cursor(p.win, { hunk_line, 0 })
        diff._accept_hunk_at_cursor()
        assert.is_true(p.files[1].hunks[1].accepted)
      end)

      it("is a no-op when cursor is on a non-hunk line (file header)", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        vim.api.nvim_win_set_cursor(p.win, { 1, 0 })
        diff.reject_hunk(1, 1)
        assert.has_no.errors(function() diff._accept_hunk_at_cursor() end)
        assert.is_false(p.files[1].hunks[1].accepted)
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

      it("_goto_next_hunk is a no-op when already at last hunk", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        local last = p.hunk_starts[#p.hunk_starts]
        vim.api.nvim_win_set_cursor(p.win, { last, 0 })
        diff._goto_next_hunk()
        local cursor = vim.api.nvim_win_get_cursor(p.win)
        assert.equals(last, cursor[1])
      end)

      it("_goto_prev_hunk is a no-op when already at first hunk", function()
        diff.open("diff --git a/a.lua b/a.lua\n@@ -1,1 +1,1 @@\n-a\n+b\n", nil, {})
        local p = diff.get_pending()
        local first = p.hunk_starts[1]
        vim.api.nvim_win_set_cursor(p.win, { first, 0 })
        diff._goto_prev_hunk()
        local cursor = vim.api.nvim_win_get_cursor(p.win)
        assert.equals(first, cursor[1])
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

  -- ── Phase 7: diffsplit layout ────────────────────────────────────
  describe("diffsplit layout", function()
    -- Patch source: a single-file modify with simple change.
    local single_file_patch = table.concat({
      "diff --git a/foo.lua b/foo.lua",
      "--- a/foo.lua",
      "+++ b/foo.lua",
      "@@ -1,2 +1,2 @@",
      "-old",
      " same",
    }, "\n")

    local tmpdir, foo_path

    before_each(function()
      -- Stubs for tabline / autocmd helpers not in vim mock
      _G.vim.api.nvim_win_set_cursor = _G.vim.api.nvim_win_set_cursor or function() end
      _G.vim.fn.fnamemodify = _G.vim.fn.fnamemodify or function(p) return p end
      _G.vim.fn.fnameescape = _G.vim.fn.fnameescape or function(p) return p end
      _G.vim.fn.getcwd      = _G.vim.fn.getcwd      or function() return "/tmp/codex_test" end

      -- Real on-disk file so compute_new_lines can read original_lines
      tmpdir = "/tmp/codex_diff_test_" .. tostring(math.random(1, 1e9))
      os.execute("mkdir -p " .. tmpdir)
      foo_path = tmpdir .. "/foo.lua"
      local f = io.open(foo_path, "wb"); f:write("old\nsame\n"); f:close()
      -- Make getcwd return tmpdir so diff.lua resolves a/foo.lua → tmpdir/foo.lua
      _G.vim.fn.getcwd = function() return tmpdir end
    end)

    after_each(function()
      if tmpdir then
        os.execute("rm -rf " .. tmpdir)
        tmpdir = nil
      end
    end)

    it("M.open with layout='diffsplit' sets pending.layout", function()
      diff.open(single_file_patch, nil, { layout = "diffsplit" })
      assert.equals("diffsplit", diff.get_pending().layout)
    end)

    it("creates a tab and stores tab_id per file", function()
      diff.open(single_file_patch, nil, { layout = "diffsplit" })
      local f = diff.get_pending().files[1]
      assert.is_truthy(f.tab_id)
    end)

    it("populates new_lines from disk + parsed hunks", function()
      diff.open(single_file_patch, nil, { layout = "diffsplit" })
      local f = diff.get_pending().files[1]
      assert.same({ "same" }, f.new_lines)
    end)

    it("status starts as 'pending'", function()
      diff.open(single_file_patch, nil, { layout = "diffsplit" })
      assert.equals("pending", diff.get_pending().files[1].status)
    end)

    it("right (new_buf) buffer is read-only", function()
      diff.open(single_file_patch, nil, { layout = "diffsplit" })
      local f = diff.get_pending().files[1]
      assert.equals(false, vim.api.nvim_buf_get_option(f.new_buf, "modifiable"))
      assert.equals("nofile", vim.api.nvim_buf_get_option(f.new_buf, "buftype"))
    end)

    it("buf-local var codex_diff_file_idx is set on both buffers", function()
      diff.open(single_file_patch, nil, { layout = "diffsplit" })
      local f = diff.get_pending().files[1]
      assert.equals(1, vim.api.nvim_buf_get_var(f.orig_buf, "codex_diff_file_idx"))
      assert.equals(1, vim.api.nvim_buf_get_var(f.new_buf,  "codex_diff_file_idx"))
    end)

    it("multi-file patch creates multiple tabs", function()
      local bar_path = tmpdir .. "/bar.lua"
      local f = io.open(bar_path, "wb"); f:write("x\n"); f:close()
      local multi = single_file_patch .. "\n" .. table.concat({
        "diff --git a/bar.lua b/bar.lua",
        "@@ -1,1 +1,1 @@",
        "-x",
        "+X",
      }, "\n")
      diff.open(multi, nil, { layout = "diffsplit" })
      local p = diff.get_pending()
      assert.equals(2, #p.files)
      assert.is_truthy(p.files[1].tab_id)
      assert.is_truthy(p.files[2].tab_id)
      assert.not_equals(p.files[1].tab_id, p.files[2].tab_id)
    end)

    it("falls back to unified UI when patch context mismatches", function()
      -- Original "old\nsame\n", but hunk expects "WRONG"
      local bad = table.concat({
        "diff --git a/foo.lua b/foo.lua",
        "@@ -1,2 +1,2 @@",
        "-WRONG",
        " same",
      }, "\n")
      diff.open(bad, nil, { layout = "diffsplit" })
      -- After fallback, layout was rewritten to "vertical" and unified UI ran
      local p = diff.get_pending()
      assert.equals("vertical", p.layout)
      -- unified UI uses p.buf / p.win (single window)
      assert.is_truthy(p.buf)
    end)

    it("new file kind: left buffer is empty scratch, right has full new content", function()
      local new_patch = table.concat({
        "diff --git a/newf.lua b/newf.lua",
        "new file mode 100644",
        "--- /dev/null",
        "+++ b/newf.lua",
        "@@ -0,0 +1,2 @@",
        "+hello",
        "+world",
      }, "\n")
      diff.open(new_patch, nil, { layout = "diffsplit" })
      local f = diff.get_pending().files[1]
      assert.equals("new", f.kind)
      assert.same({ "hello", "world" }, f.new_lines)
    end)

    -- ── state machine: accept/deny per file + finalize ────────────
    describe("state machine", function()
      local function multi_patch(bar_path)
        -- Need bar.lua on disk too
        local f = io.open(bar_path, "wb"); f:write("x\n"); f:close()
        return single_file_patch .. "\n" .. table.concat({
          "diff --git a/bar.lua b/bar.lua",
          "@@ -1,1 +1,1 @@",
          "-x",
          "+X",
        }, "\n")
      end

      it("accept_current marks current file accepted", function()
        diff.open(single_file_patch, nil, { layout = "diffsplit" })
        local p = diff.get_pending()
        vim.api.nvim_set_current_tabpage(p.files[1].tab_id)
        diff.accept_current()
        -- single-file path: also finalizes (all decided) → pending cleared
        assert.is_false(diff.has_pending())
      end)

      it("deny_current marks current file denied + finalize", function()
        local result
        diff.open(single_file_patch, function(r) result = r end, { layout = "diffsplit" })
        local p = diff.get_pending()
        vim.api.nvim_set_current_tabpage(p.files[1].tab_id)
        diff.deny_current()
        assert.equals("denied", result.decision)
      end)

      it("accept_current responds approved after single file accepted", function()
        local result
        diff.open(single_file_patch, function(r) result = r end, { layout = "diffsplit" })
        local p = diff.get_pending()
        vim.api.nvim_set_current_tabpage(p.files[1].tab_id)
        diff.accept_current()
        assert.equals("approved", result.decision)
      end)

      it("multi-file: each accept_current moves to next pending tab", function()
        local bar_path = tmpdir .. "/bar.lua"
        diff.open(multi_patch(bar_path), nil, { layout = "diffsplit" })
        local p = diff.get_pending()
        local tab1, tab2 = p.files[1].tab_id, p.files[2].tab_id
        vim.api.nvim_set_current_tabpage(tab1)
        diff.accept_current()
        -- After accept tab1, should still have pending, current tab should be tab2
        assert.is_true(diff.has_pending())
        assert.equals("accepted", diff.get_pending().files[1].status)
        assert.equals(tab2, vim.api.nvim_get_current_tabpage())
      end)

      it("multi-file: after all decided, finalize with approved if any accepted", function()
        local result
        local bar_path = tmpdir .. "/bar.lua"
        diff.open(multi_patch(bar_path), function(r) result = r end, { layout = "diffsplit" })
        local p = diff.get_pending()
        vim.api.nvim_set_current_tabpage(p.files[1].tab_id)
        diff.accept_current()
        vim.api.nvim_set_current_tabpage(p.files[2].tab_id)
        diff.deny_current()
        assert.equals("approved", result.decision)
        assert.is_false(diff.has_pending())
      end)

      it("multi-file: all denied → respond_fn denied", function()
        local result
        local bar_path = tmpdir .. "/bar.lua"
        diff.open(multi_patch(bar_path), function(r) result = r end, { layout = "diffsplit" })
        local p = diff.get_pending()
        vim.api.nvim_set_current_tabpage(p.files[1].tab_id)
        diff.deny_current()
        vim.api.nvim_set_current_tabpage(p.files[2].tab_id)
        diff.deny_current()
        assert.equals("denied", result.decision)
      end)

      it("accept_all in diffsplit marks all pending and finalizes approved", function()
        local result
        local bar_path = tmpdir .. "/bar.lua"
        diff.open(multi_patch(bar_path), function(r) result = r end, { layout = "diffsplit" })
        diff.accept_all()
        assert.equals("approved", result.decision)
        assert.is_false(diff.has_pending())
      end)

      it("deny_all in diffsplit marks all pending and finalizes denied", function()
        local result
        local bar_path = tmpdir .. "/bar.lua"
        diff.open(multi_patch(bar_path), function(r) result = r end, { layout = "diffsplit" })
        diff.deny_all()
        assert.equals("denied", result.decision)
        assert.is_false(diff.has_pending())
      end)

      it("accept_current in unified mode delegates to accept_all", function()
        local result
        diff.open(single_file_patch, function(r) result = r end, {})  -- no layout
        diff.accept_current()
        assert.equals("approved", result.decision)
      end)

      it("deny_current in unified mode delegates to deny_all", function()
        local result
        diff.open(single_file_patch, function(r) result = r end, {})
        diff.deny_current()
        assert.equals("denied", result.decision)
      end)
    end)

    -- ── TabClosed autocmd: user closing a pending tab = deny ──────
    describe("TabClosed autocmd", function()
      it("pending tab closed → file marked denied + finalize", function()
        local result
        diff.open(single_file_patch, function(r) result = r end, { layout = "diffsplit" })
        local p = diff.get_pending()
        local tab_id = p.files[1].tab_id
        -- Simulate user closing the tab
        vim.api.nvim_set_current_tabpage(tab_id)
        vim.cmd("tabclose")
        -- Then fire TabClosed manually (mock doesn't fire it from tabclose)
        vim._mock.fire_autocmd("TabClosed", {})
        assert.is_false(diff.has_pending())
        assert.equals("denied", result.decision)
      end)

      it("multi-file: closing one tab denies that file, others remain", function()
        local bar_path = tmpdir .. "/bar.lua"
        local f = io.open(bar_path, "wb"); f:write("x\n"); f:close()
        local multi = single_file_patch .. "\n" .. table.concat({
          "diff --git a/bar.lua b/bar.lua",
          "@@ -1,1 +1,1 @@",
          "-x",
          "+X",
        }, "\n")
        diff.open(multi, nil, { layout = "diffsplit" })
        local p = diff.get_pending()
        local tab1 = p.files[1].tab_id
        vim.api.nvim_set_current_tabpage(tab1)
        vim.cmd("tabclose")
        vim._mock.fire_autocmd("TabClosed", {})
        -- file1 should be denied, file2 still pending
        assert.is_true(diff.has_pending())
        assert.equals("denied",  diff.get_pending().files[1].status)
        assert.equals("pending", diff.get_pending().files[2].status)
      end)
    end)
  end)
end)
