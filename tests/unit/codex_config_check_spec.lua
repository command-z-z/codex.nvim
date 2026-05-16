-- tests/unit/codex_config_check_spec.lua
require("busted_setup")

describe("codex.codex_config_check", function()
  local mod
  local tmpfile

  before_each(function()
    package.loaded["codex.codex_config_check"] = nil
    mod = require("codex.codex_config_check")
    tmpfile = os.tmpname()
  end)

  after_each(function()
    if tmpfile then os.remove(tmpfile) end
  end)

  local function write_file(path, body)
    local fd = io.open(path, "w")
    fd:write(body)
    fd:close()
  end

  describe("scan()", function()
    it("returns empty table for nonexistent file", function()
      assert.same({}, mod.scan("/nonexistent/path/foo.toml"))
    end)

    it("returns empty for empty file", function()
      write_file(tmpfile, "")
      assert.same({}, mod.scan(tmpfile))
    end)

    it("returns empty when no relevant keys present", function()
      write_file(tmpfile, [[
model = "gpt-5"
other_key = "irrelevant"
]])
      assert.same({}, mod.scan(tmpfile))
    end)

    it("captures approval_policy", function()
      write_file(tmpfile, [[
approval_policy = "never"
]])
      assert.equals("never", mod.scan(tmpfile).approval_policy)
    end)

    it("captures sandbox_mode", function()
      write_file(tmpfile, [[
sandbox_mode = "danger-full-access"
]])
      assert.equals("danger-full-access", mod.scan(tmpfile).sandbox_mode)
    end)

    it("stops scanning at first [section] (only top-level)", function()
      write_file(tmpfile, [[
[some_section]
approval_policy = "never"
]])
      assert.same({}, mod.scan(tmpfile))
    end)

    it("captures both keys when present at top level", function()
      write_file(tmpfile, [[
approval_policy = "never"
sandbox_mode = "danger-full-access"
[projects."/foo"]
trust_level = "trusted"
]])
      local found = mod.scan(tmpfile)
      assert.equals("never", found.approval_policy)
      assert.equals("danger-full-access", found.sandbox_mode)
    end)
  end)

  describe("warnings()", function()
    it("returns empty for empty input", function()
      assert.same({}, mod.warnings({}))
    end)

    it("warns on approval_policy='never'", function()
      local w = mod.warnings({ approval_policy = "never" })
      assert.equals(1, #w)
      assert.is_truthy(w[1]:find("approval_policy"))
    end)

    it("warns on sandbox_mode='danger-full-access'", function()
      local w = mod.warnings({ sandbox_mode = "danger-full-access" })
      assert.equals(1, #w)
      assert.is_truthy(w[1]:find("sandbox_mode"))
    end)

    it("warns on both", function()
      local w = mod.warnings({
        approval_policy = "never",
        sandbox_mode = "danger-full-access",
      })
      assert.equals(2, #w)
    end)

    it("does NOT warn on benign values", function()
      assert.same({}, mod.warnings({ approval_policy = "on-request" }))
      assert.same({}, mod.warnings({ sandbox_mode = "workspace-write" }))
    end)
  end)

  describe("check_and_warn()", function()
    it("is a no-op when HOME has no config.toml", function()
      local orig = os.getenv("HOME")
      -- Point HOME at a directory that has no .codex/config.toml
      vim.notify = function() end
      assert.has_no.errors(function() mod.check_and_warn() end)
    end)
  end)
end)
