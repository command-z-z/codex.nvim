-- tests/unit/diff_patch_spec.lua
require("busted_setup")

describe("codex.diff_patch", function()
  local diff_patch

  before_each(function()
    package.loaded["codex.diff_patch"] = nil
    diff_patch = require("codex.diff_patch")
  end)

  -- ── parse_hunk_header ─────────────────────────────────────────
  describe("parse_hunk_header()", function()
    it("parses standard '@@ -1,3 +1,4 @@'", function()
      local os, oc, ns, nc = diff_patch.parse_hunk_header("@@ -1,3 +1,4 @@")
      assert.equals(1, os)
      assert.equals(3, oc)
      assert.equals(1, ns)
      assert.equals(4, nc)
    end)

    it("defaults count to 1 when omitted: '@@ -5 +5 @@'", function()
      local os, oc, ns, nc = diff_patch.parse_hunk_header("@@ -5 +5 @@")
      assert.equals(5, os)
      assert.equals(1, oc)
      assert.equals(5, ns)
      assert.equals(1, nc)
    end)

    it("parses 0-line new file '@@ -0,0 +1,2 @@'", function()
      local os, oc, ns, nc = diff_patch.parse_hunk_header("@@ -0,0 +1,2 @@")
      assert.equals(0, os)
      assert.equals(0, oc)
      assert.equals(1, ns)
      assert.equals(2, nc)
    end)

    it("returns nil for malformed header", function()
      assert.is_nil(diff_patch.parse_hunk_header("not a hunk header"))
    end)

    it("accepts trailing section name: '@@ -1,3 +1,3 @@ function foo'", function()
      local os = diff_patch.parse_hunk_header("@@ -1,3 +1,3 @@ function foo")
      assert.equals(1, os)
    end)
  end)

  -- ── apply_hunks ───────────────────────────────────────────────
  describe("apply_hunks()", function()
    it("single hunk: add line", function()
      local orig = { "a", "b", "c" }
      local hunks = {
        { header = "@@ -1,3 +1,4 @@", lines = { " a", "+new", " b", " c" } },
      }
      local result, ok = diff_patch.apply_hunks(orig, hunks)
      assert.is_true(ok)
      assert.same({ "a", "new", "b", "c" }, result)
    end)

    it("single hunk: delete line", function()
      local orig = { "a", "b", "c" }
      local hunks = {
        { header = "@@ -1,3 +1,2 @@", lines = { " a", "-b", " c" } },
      }
      local result, ok = diff_patch.apply_hunks(orig, hunks)
      assert.is_true(ok)
      assert.same({ "a", "c" }, result)
    end)

    it("single hunk: replace line (delete + add)", function()
      local orig = { "a", "old", "c" }
      local hunks = {
        { header = "@@ -1,3 +1,3 @@", lines = { " a", "-old", "+new", " c" } },
      }
      local result, ok = diff_patch.apply_hunks(orig, hunks)
      assert.is_true(ok)
      assert.same({ "a", "new", "c" }, result)
    end)

    it("multi hunk: skips intervening untouched lines", function()
      local orig = { "1", "2", "3", "4", "5", "6", "7" }
      local hunks = {
        { header = "@@ -1,2 +1,2 @@", lines = { "-1", "+ONE", " 2" } },
        { header = "@@ -6,2 +6,2 @@", lines = { "-6", "+SIX", " 7" } },
      }
      local result, ok = diff_patch.apply_hunks(orig, hunks)
      assert.is_true(ok)
      assert.same({ "ONE", "2", "3", "4", "5", "SIX", "7" }, result)
    end)

    it("new file: all + lines, empty original", function()
      local hunks = {
        { header = "@@ -0,0 +1,2 @@", lines = { "+line1", "+line2" } },
      }
      local result, ok = diff_patch.apply_hunks({}, hunks)
      assert.is_true(ok)
      assert.same({ "line1", "line2" }, result)
    end)

    it("context mismatch returns error", function()
      local orig = { "a", "b", "c" }
      local hunks = {
        { header = "@@ -1,3 +1,3 @@", lines = { " a", "-WRONG", "+x", " c" } },
      }
      local result, ok, err = diff_patch.apply_hunks(orig, hunks)
      assert.is_false(ok)
      assert.is_truthy(err:find("mismatch"))
    end)

    it("bad hunk header returns error", function()
      local orig = { "a" }
      local hunks = { { header = "@@ broken @@", lines = {} } }
      local _, ok, err = diff_patch.apply_hunks(orig, hunks)
      assert.is_false(ok)
      assert.is_truthy(err:find("bad hunk header"))
    end)

    it("'\\ No newline at end of file' marker is ignored", function()
      local orig = { "a", "b" }
      local hunks = {
        { header = "@@ -1,2 +1,2 @@",
          lines = { " a", "-b", "\\ No newline at end of file", "+c" } },
      }
      local result, ok = diff_patch.apply_hunks(orig, hunks)
      assert.is_true(ok)
      assert.same({ "a", "c" }, result)
    end)

    it("preserves lines after final hunk", function()
      local orig = { "a", "b", "c", "d", "e" }
      local hunks = {
        { header = "@@ -1,1 +1,1 @@", lines = { "-a", "+A" } },
      }
      local result, ok = diff_patch.apply_hunks(orig, hunks)
      assert.is_true(ok)
      assert.same({ "A", "b", "c", "d", "e" }, result)
    end)
  end)

  -- ── compute_new_lines ─────────────────────────────────────────
  describe("compute_new_lines()", function()
    local tmpfile

    before_each(function()
      tmpfile = os.tmpname()
    end)

    after_each(function()
      if tmpfile then os.remove(tmpfile) end
    end)

    local function write_file(path, lines)
      local fd = io.open(path, "wb")
      fd:write(table.concat(lines, "\n") .. "\n")
      fd:close()
    end

    it("binary file returns error", function()
      local file = { binary = true, kind = "binary", hunks = {} }
      local _, ok, err = diff_patch.compute_new_lines(file, tmpfile)
      assert.is_false(ok)
      assert.equals("binary", err)
    end)

    it("delete kind returns empty array", function()
      local file = { kind = "delete", hunks = {}, binary = false }
      local result, ok = diff_patch.compute_new_lines(file, tmpfile)
      assert.is_true(ok)
      assert.same({}, result)
    end)

    it("modify kind reads disk + applies hunks", function()
      write_file(tmpfile, { "a", "b", "c" })
      local file = {
        kind = "modify", binary = false,
        hunks = {
          { header = "@@ -1,3 +1,3 @@", lines = { " a", "-b", "+B", " c" } },
        },
      }
      local result, ok = diff_patch.compute_new_lines(file, tmpfile)
      assert.is_true(ok)
      assert.same({ "a", "B", "c" }, result)
    end)

    it("new kind ignores disk, applies hunks to empty original", function()
      local file = {
        kind = "new", binary = false,
        hunks = {
          { header = "@@ -0,0 +1,2 @@", lines = { "+hello", "+world" } },
        },
      }
      local result, ok = diff_patch.compute_new_lines(file, "/nonexistent/path")
      assert.is_true(ok)
      assert.same({ "hello", "world" }, result)
    end)

    it("modify kind: missing file returns error", function()
      local file = { kind = "modify", binary = false, hunks = {} }
      local _, ok, err = diff_patch.compute_new_lines(file, "/definitely/missing/path")
      assert.is_false(ok)
      assert.is_truthy(err:find("cannot read"))
    end)
  end)
end)
