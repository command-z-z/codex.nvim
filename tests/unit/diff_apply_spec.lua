-- tests/unit/diff_apply_spec.lua
require("busted_setup")

describe("codex.handlers", function()
  local handlers
  local diff_mock
  local approval_policy

  before_each(function()
    package.loaded["codex.handlers.init"] = nil
    package.loaded["codex.handlers.diff_apply"] = nil
    approval_policy = "prompt"

    diff_mock = {
      open_calls = {},
      open = function(patch, respond_fn, opts)
        table.insert(diff_mock.open_calls, { patch = patch, respond_fn = respond_fn, opts = opts })
      end,
    }
    package.preload["codex.diff"] = function() return diff_mock end
    -- Dynamic mock so reads of `.state` reflect the current approval_policy
    -- after a test reassigns the upvalue.
    package.preload["codex"] = function()
      return setmetatable({}, {
        __index = function(_, k)
          if k == "state" then
            return { config = { diff_opts = { layout = "vertical" }, approval = { policy = approval_policy } } }
          end
        end,
      })
    end

    handlers = require("codex.handlers.init")
  end)

  after_each(function()
    package.preload["codex.diff"] = nil
    package.preload["codex"] = nil
    package.loaded["codex.diff"] = nil
    package.loaded["codex"] = nil
  end)

  -- ── handlers/init.lua — dispatcher ────────────────────────────
  describe("handlers/init.lua", function()
    it("handle_notification: unknown method is a no-op", function()
      assert.has_no.errors(function()
        handlers.handle_notification("$/unknown", {})
      end)
    end)

    it("handle_request: unknown method responds with error code -32601", function()
      local err = nil
      handlers.handle_request("$/unknown", {}, function(_, e) err = e end)
      assert.is_not_nil(err)
      assert.equals(-32601, err.code)
    end)

    it("handle_notification: calls registered handler's on_notification", function()
      local called_params = nil
      handlers.register("$/test", {
        on_notification = function(params) called_params = params end,
      })
      handlers.handle_notification("$/test", { x = 42 })
      assert.equals(42, called_params.x)
    end)

    it("handle_request: calls registered handler's on_request with respond", function()
      local got_respond = nil
      local got_method = nil
      handlers.register("$/test", {
        on_request = function(_, respond, method) got_respond = respond; got_method = method end,
      })
      local my_respond = function() end
      handlers.handle_request("$/test", {}, my_respond)
      assert.equals(my_respond, got_respond)
      assert.equals("$/test", got_method)
    end)

    it("handle_notification: no error when handler has no on_notification field", function()
      handlers.register("$/test", { on_request = function() end })
      assert.has_no.errors(function()
        handlers.handle_notification("$/test", {})
      end)
    end)

    it("handle_request: nil respond is safe for unknown method", function()
      assert.has_no.errors(function()
        handlers.handle_request("$/unknown", {}, nil)
      end)
    end)
  end)

  -- ── handlers/diff_apply.lua ────────────────────────────────────
  describe("handlers/diff_apply.lua", function()
    local diff_apply

    before_each(function()
      package.loaded["codex.handlers.diff_apply"] = nil
      diff_apply = require("codex.handlers.diff_apply")
    end)

    it("on_request calls diff.open with params.patch", function()
      local respond = function() end
      diff_apply.on_request({ patch = "the patch" }, respond)
      assert.equals(1, #diff_mock.open_calls)
      assert.equals("the patch", diff_mock.open_calls[1].patch)
    end)

    it("on_request passes the respond callback to diff.open", function()
      local respond = function() end
      diff_apply.on_request({ patch = "p" }, respond)
      assert.equals(respond, diff_mock.open_calls[1].respond_fn)
    end)

    it("on_request falls back to params.diff when no patch key", function()
      diff_apply.on_request({ diff = "diff text" }, function() end)
      assert.equals("diff text", diff_mock.open_calls[1].patch)
    end)

    it("on_request renders applyPatchApproval fileChanges", function()
      diff_apply.on_request({
        fileChanges = {
          ["ai.lua"] = {
            type = "update",
            unified_diff = "--- a/ai.lua\n+++ b/ai.lua\n@@ -1 +1 @@\n-old\n+new\n",
          },
        },
      }, function() end, "applyPatchApproval")
      local patch = diff_mock.open_calls[1].patch
      assert.is_truthy(patch:find("diff --git a/ai.lua b/ai.lua", 1, true))
      assert.is_truthy(patch:find("@@ -1 +1 @@", 1, true))
    end)

    it("on_request renders added fileChanges content", function()
      diff_apply.on_request({
        fileChanges = {
          ["new.lua"] = {
            type = "add",
            content = "one\ntwo\n",
          },
        },
      }, function() end, "applyPatchApproval")
      local patch = diff_mock.open_calls[1].patch
      assert.is_truthy(patch:find("new file mode", 1, true))
      assert.is_truthy(patch:find("+one", 1, true))
      assert.is_truthy(patch:find("+two", 1, true))
    end)

    it("on_request denies when no patch can be found", function()
      local result
      diff_apply.on_request({}, function(r) result = r end, "applyPatchApproval")
      assert.equals(0, #diff_mock.open_calls)
      assert.same({ decision = "denied" }, result)
    end)

    it("on_request auto-approves without opening diff when approval policy is auto-allow", function()
      approval_policy = "auto-allow"
      local result
      diff_apply.on_request({ patch = "p" }, function(r) result = r end, "applyPatchApproval")
      assert.equals(0, #diff_mock.open_calls)
      assert.same({ decision = "approved" }, result)
    end)

    it("on_request auto-denies without opening diff when approval policy is auto-deny", function()
      approval_policy = "auto-deny"
      local result
      diff_apply.on_request({ patch = "p" }, function(r) result = r end, "item/fileChange/requestApproval")
      assert.equals(0, #diff_mock.open_calls)
      assert.same({ decision = "decline" }, result)
    end)

    it("on_request opens diff when policy=prompt + valid patch (Phase 8 sanity)", function()
      approval_policy = "prompt"
      diff_apply.on_request(
        { patch = "diff --git a/x b/x\n@@ -1 +1 @@\n-a\n+b\n" },
        function() end,
        "item/fileChange/requestApproval"
      )
      assert.equals(1, #diff_mock.open_calls)
      -- The wrapper for fileChange method gets passed instead of raw respond
      assert.is_truthy(diff_mock.open_calls[1].respond_fn)
    end)

    it("on_request passes diff_opts from config", function()
      diff_apply.on_request({ patch = "p" }, function() end)
      assert.equals("vertical", diff_mock.open_calls[1].opts.layout)
    end)

    it("on_notification calls diff.open with nil respond_fn", function()
      diff_apply.on_notification({ patch = "patch data" })
      assert.equals(1, #diff_mock.open_calls)
      assert.is_nil(diff_mock.open_calls[1].respond_fn)
    end)

    it("on_notification passes the patch string", function()
      diff_apply.on_notification({ patch = "notif patch" })
      assert.equals("notif patch", diff_mock.open_calls[1].patch)
    end)

    it("on_notification caches turn/diff/updated diff for later fileChange approval", function()
      diff_apply.on_notification({
        threadId = "thread-1",
        turnId = "turn-1",
        diff = "diff --git a/ai.lua b/ai.lua\n@@ -1 +1 @@\n-a\n+b\n",
      }, "turn/diff/updated")

      local result
      diff_apply.on_request({ turnId = "turn-1" }, function(r) result = r end, "item/fileChange/requestApproval")
      assert.equals(2, #diff_mock.open_calls)
      assert.equals("diff --git a/ai.lua b/ai.lua\n@@ -1 +1 @@\n-a\n+b\n", diff_mock.open_calls[2].patch)

      diff_mock.open_calls[2].respond_fn({ decision = "approved" })
      assert.same({ decision = "accept" }, result)
    end)

    it("on_notification caches item/fileChange/patchUpdated changes by itemId", function()
      diff_apply.on_notification({
        itemId = "item-1",
        changes = {
          {
            path = "ai.lua",
            kind = { type = "update" },
            diff = "--- a/ai.lua\n+++ b/ai.lua\n@@ -1 +1 @@\n-a\n+b\n",
          },
        },
      }, "item/fileChange/patchUpdated")

      diff_apply.on_request({ itemId = "item-1" }, function() end, "item/fileChange/requestApproval")
      assert.equals(2, #diff_mock.open_calls)
      assert.is_truthy(diff_mock.open_calls[2].patch:find("diff --git a/ai.lua b/ai.lua", 1, true))
    end)

    it("on_notification passes diff_opts from config", function()
      diff_apply.on_notification({ patch = "p" })
      assert.equals("vertical", diff_mock.open_calls[1].opts.layout)
    end)

    it("on_request is safe when params is nil", function()
      assert.has_no.errors(function()
        diff_apply.on_request(nil, function() end)
      end)
    end)

    it("on_notification is safe when params is nil", function()
      assert.has_no.errors(function()
        diff_apply.on_notification(nil)
      end)
    end)
  end)

  describe("handlers/init.lua setup() registers approval methods", function()
    local approval_mock

    before_each(function()
      package.loaded["codex.handlers.init"] = nil
      approval_mock = {
        APPROVAL_METHODS = {
          "item/commandExecution/requestApproval",
          "item/permissions/requestApproval",
          "item/fileChange/requestApproval",
          "applyPatchApproval",
          "item/tool/requestUserInput",
          "mcpServer/elicitation/request",
        },
        handle_calls = {},
        handle = function(method, params, respond)
          table.insert(approval_mock.handle_calls, { method = method })
          respond({ decision = "denied" }, nil)
        end,
      }
      package.preload["codex.handlers.approval"] = function() return approval_mock end
      handlers = require("codex.handlers.init")
      handlers.setup()
    end)

    after_each(function()
      package.preload["codex.handlers.approval"] = nil
      package.loaded["codex.handlers.approval"] = nil
    end)

    it("registers handler for item/commandExecution/requestApproval", function()
      local responded = false
      handlers.handle_request("item/commandExecution/requestApproval", {}, function() responded = true end)
      assert.is_true(responded)
    end)

    it("registers handler for applyPatchApproval", function()
      local responded = false
      handlers.handle_request("applyPatchApproval", {}, function() responded = true end)
      assert.is_true(responded)
    end)

    it("routes request through approval.handle with correct method", function()
      handlers.handle_request("item/permissions/requestApproval", {}, function() end)
      assert.equals(1, #approval_mock.handle_calls)
      assert.equals("item/permissions/requestApproval", approval_mock.handle_calls[1].method)
    end)
  end)
end)
