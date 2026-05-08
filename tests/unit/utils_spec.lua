require("busted_setup")

describe("codex.utils", function()
  local utils

  before_each(function()
    package.loaded["codex.utils"] = nil
    utils = require("codex.utils")
  end)

  describe("normalize_focus()", function()
    it("returns true when focus is nil (backward-compat default)", function()
      assert.is_true(utils.normalize_focus(nil))
    end)
    it("returns true when focus is true", function()
      assert.is_true(utils.normalize_focus(true))
    end)
    it("returns false when focus is false", function()
      assert.is_false(utils.normalize_focus(false))
    end)
  end)
end)
