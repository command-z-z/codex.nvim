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
end)
