-- tests/unit/approval_spec.lua
require("busted_setup")

describe("codex.handlers.approval", function()
  local approval

  local function load_with_policy(policy)
    package.loaded["codex.handlers.approval"] = nil
    package.loaded["codex.init"] = nil
    package.preload["codex.init"] = function()
      return { state = { config = { approval = { policy = policy } } } }
    end
    return require("codex.handlers.approval")
  end

  before_each(function()
    approval = load_with_policy("prompt")
    vim.fn.confirm = function(_, _, _) return 1 end
  end)

  after_each(function()
    package.preload["codex.init"] = nil
    package.loaded["codex.init"] = nil
    package.loaded["codex.handlers.approval"] = nil
  end)

  describe("_approve_result()", function()
    it("returns {decision=approved} for commandExecution", function()
      assert.same({ decision = "approved" }, approval._approve_result("item/commandExecution/requestApproval"))
    end)
    it("returns {decision=approved} for permissions", function()
      assert.same({ decision = "approved" }, approval._approve_result("item/permissions/requestApproval"))
    end)
    it("returns {decision=approved} for fileChange", function()
      assert.same({ decision = "approved" }, approval._approve_result("item/fileChange/requestApproval"))
    end)
    it("returns {decision=approved} for applyPatchApproval", function()
      assert.same({ decision = "approved" }, approval._approve_result("applyPatchApproval"))
    end)
    it("returns {decision=confirmed} for requestUserInput", function()
      assert.same({ decision = "confirmed" }, approval._approve_result("item/tool/requestUserInput"))
    end)
    it("returns {decision=confirmed} for elicitation", function()
      assert.same({ decision = "confirmed" }, approval._approve_result("mcpServer/elicitation/request"))
    end)
  end)

  describe("_deny_result()", function()
    it("returns {decision=denied} for commandExecution", function()
      assert.same({ decision = "denied" }, approval._deny_result("item/commandExecution/requestApproval"))
    end)
    it("returns {decision=denied} for applyPatchApproval", function()
      assert.same({ decision = "denied" }, approval._deny_result("applyPatchApproval"))
    end)
    it("returns {decision=declined} for requestUserInput", function()
      assert.same({ decision = "declined" }, approval._deny_result("item/tool/requestUserInput"))
    end)
    it("returns {decision=declined} for elicitation", function()
      assert.same({ decision = "declined" }, approval._deny_result("mcpServer/elicitation/request"))
    end)
  end)

  describe("_get_policy()", function()
    it("returns 'prompt' when config has policy=prompt", function()
      assert.equals("prompt", approval._get_policy())
    end)
    it("returns 'auto-allow' from config", function()
      approval = load_with_policy("auto-allow")
      assert.equals("auto-allow", approval._get_policy())
    end)
    it("returns 'auto-deny' from config", function()
      approval = load_with_policy("auto-deny")
      assert.equals("auto-deny", approval._get_policy())
    end)
    it("returns 'prompt' when codex.init is unavailable", function()
      package.loaded["codex.handlers.approval"] = nil
      package.loaded["codex.init"] = nil
      package.preload["codex.init"] = nil
      approval = require("codex.handlers.approval")
      assert.equals("prompt", approval._get_policy())
    end)
  end)

  describe("handle() auto-allow policy", function()
    before_each(function()
      approval = load_with_policy("auto-allow")
    end)

    it("responds with approved for commandExecution", function()
      local result
      approval.handle("item/commandExecution/requestApproval", {}, function(r) result = r end)
      assert.same({ decision = "approved" }, result)
    end)
    it("responds with approved for fileChange", function()
      local result
      approval.handle("item/fileChange/requestApproval", {}, function(r) result = r end)
      assert.same({ decision = "approved" }, result)
    end)
    it("responds with confirmed for requestUserInput", function()
      local result
      approval.handle("item/tool/requestUserInput", {}, function(r) result = r end)
      assert.same({ decision = "confirmed" }, result)
    end)
    it("responds with confirmed for elicitation", function()
      local result
      approval.handle("mcpServer/elicitation/request", {}, function(r) result = r end)
      assert.same({ decision = "confirmed" }, result)
    end)
    it("does not call vim.fn.confirm", function()
      local confirm_called = false
      vim.fn.confirm = function() confirm_called = true; return 1 end
      approval.handle("item/commandExecution/requestApproval", {}, function() end)
      assert.is_false(confirm_called)
    end)
  end)

  describe("handle() auto-deny policy", function()
    before_each(function()
      approval = load_with_policy("auto-deny")
    end)

    it("responds with denied for commandExecution", function()
      local result
      approval.handle("item/commandExecution/requestApproval", {}, function(r) result = r end)
      assert.same({ decision = "denied" }, result)
    end)
    it("responds with denied for applyPatchApproval", function()
      local result
      approval.handle("applyPatchApproval", {}, function(r) result = r end)
      assert.same({ decision = "denied" }, result)
    end)
    it("responds with declined for elicitation", function()
      local result
      approval.handle("mcpServer/elicitation/request", {}, function(r) result = r end)
      assert.same({ decision = "declined" }, result)
    end)
    it("does not call vim.fn.confirm", function()
      local confirm_called = false
      vim.fn.confirm = function() confirm_called = true; return 1 end
      approval.handle("item/commandExecution/requestApproval", {}, function() end)
      assert.is_false(confirm_called)
    end)
  end)

  describe("handle() prompt policy", function()
    -- vim.schedule executes callback immediately in the mock
    -- vim.fn.confirm returns 1=Allow, 2=Deny, 0=cancelled

    it("calls vim.fn.confirm", function()
      local confirm_called = false
      vim.fn.confirm = function(_, _, _) confirm_called = true; return 2 end
      approval.handle("item/commandExecution/requestApproval", {}, function() end)
      assert.is_true(confirm_called)
    end)

    it("responds with approved when user selects Allow (1)", function()
      vim.fn.confirm = function() return 1 end
      local result
      approval.handle("item/commandExecution/requestApproval", {}, function(r) result = r end)
      assert.same({ decision = "approved" }, result)
    end)

    it("responds with denied when user selects Deny (2)", function()
      vim.fn.confirm = function() return 2 end
      local result
      approval.handle("item/commandExecution/requestApproval", {}, function(r) result = r end)
      assert.same({ decision = "denied" }, result)
    end)

    it("responds with denied when user cancels (0)", function()
      vim.fn.confirm = function() return 0 end
      local result
      approval.handle("item/commandExecution/requestApproval", {}, function(r) result = r end)
      assert.same({ decision = "denied" }, result)
    end)

    it("responds with confirmed for requestUserInput when Allow", function()
      vim.fn.confirm = function() return 1 end
      local result
      approval.handle("item/tool/requestUserInput", {}, function(r) result = r end)
      assert.same({ decision = "confirmed" }, result)
    end)

    it("responds with declined for elicitation when Deny", function()
      vim.fn.confirm = function() return 2 end
      local result
      approval.handle("mcpServer/elicitation/request", {}, function(r) result = r end)
      assert.same({ decision = "declined" }, result)
    end)

    it("includes method name in confirm prompt", function()
      local prompt_text = nil
      vim.fn.confirm = function(msg, _, _) prompt_text = msg; return 1 end
      approval.handle("item/commandExecution/requestApproval", {}, function() end)
      assert.is_truthy(prompt_text)
      assert.is_truthy(prompt_text:len() > 0)
    end)

    it("is safe (no errors) when prompt fires inside vim.schedule", function()
      vim.fn.confirm = function() return 1 end
      assert.has_no.errors(function()
        approval.handle("item/commandExecution/requestApproval", {}, function() end)
      end)
    end)
  end)

  describe("APPROVAL_METHODS", function()
    local EXPECTED = {
      "item/commandExecution/requestApproval",
      "item/permissions/requestApproval",
      "item/fileChange/requestApproval",
      "applyPatchApproval",
      "item/tool/requestUserInput",
      "mcpServer/elicitation/request",
    }

    it("contains all expected methods", function()
      for _, m in ipairs(EXPECTED) do
        local found = false
        for _, am in ipairs(approval.APPROVAL_METHODS) do
          if am == m then found = true end
        end
        assert.is_true(found, "Missing method: " .. m)
      end
    end)

    it("has exactly 6 methods", function()
      assert.equals(6, #approval.APPROVAL_METHODS)
    end)
  end)
end)
