# Phase 5: Approval Handler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When codex app-server sends an approval request (`item/commandExecution/requestApproval`, `applyPatchApproval`, etc.), Neovim shows a prompt (or auto-responds) based on the configured `approval.policy`.

**Architecture:** `handlers/approval.lua` owns all policy logic and response-format mapping. It is registered for all known approval method names in `handlers/init.lua`'s `setup()` via closure wrappers, and also wired into `app_server.lua`'s hard-coded `ensure_respond_to_server_request` which is replaced with a lazy call through the same module. The mention queue is **already implemented** in `init.lua` — no work needed there.

**Tech Stack:** Pure Lua, `vim.fn.confirm` (blocking dialog), `vim.schedule` (deferred to main thread), busted (Lua 5.1).

---

## File Map

| File | Role |
|------|------|
| `lua/codex/handlers/approval.lua` | Policy-based approval: auto-allow, auto-deny, prompt |
| `lua/codex/handlers/init.lua` | Modified: register all approval methods in `setup()` |
| `lua/codex/app_server.lua` | Modified: replace hard-coded deny with `approval.handle()` call |
| `tests/unit/approval_spec.lua` | Tests for all three policies, response format mapping |
| `tests/unit/diff_apply_spec.lua` | Extended: verify approval methods are registered after `setup()` |

---

## Task 1: handlers/approval.lua — policy logic + tests

**Files:**
- Create: `lua/codex/handlers/approval.lua`
- Create: `tests/unit/approval_spec.lua`

- [ ] **Step 1: Write the failing tests**

```lua
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
    -- Add confirm mock (not in default vim mock)
    vim.fn.confirm = function(_, _, _) return 1 end
  end)

  after_each(function()
    package.preload["codex.init"] = nil
    package.loaded["codex.init"] = nil
    package.loaded["codex.handlers.approval"] = nil
  end)

  -- ── _approve_result ────────────────────────────────────────────
  describe("_approve_result()", function()
    it("returns {decision=approved} for commandExecution", function()
      assert.same({ decision = "approved" },
        approval._approve_result("item/commandExecution/requestApproval"))
    end)
    it("returns {decision=approved} for permissions", function()
      assert.same({ decision = "approved" },
        approval._approve_result("item/permissions/requestApproval"))
    end)
    it("returns {decision=approved} for fileChange", function()
      assert.same({ decision = "approved" },
        approval._approve_result("item/fileChange/requestApproval"))
    end)
    it("returns {decision=approved} for applyPatchApproval", function()
      assert.same({ decision = "approved" },
        approval._approve_result("applyPatchApproval"))
    end)
    it("returns {decision=confirmed} for requestUserInput", function()
      assert.same({ decision = "confirmed" },
        approval._approve_result("item/tool/requestUserInput"))
    end)
    it("returns {decision=confirmed} for elicitation", function()
      assert.same({ decision = "confirmed" },
        approval._approve_result("mcpServer/elicitation/request"))
    end)
  end)

  -- ── _deny_result ───────────────────────────────────────────────
  describe("_deny_result()", function()
    it("returns {decision=denied} for commandExecution", function()
      assert.same({ decision = "denied" },
        approval._deny_result("item/commandExecution/requestApproval"))
    end)
    it("returns {decision=denied} for applyPatchApproval", function()
      assert.same({ decision = "denied" },
        approval._deny_result("applyPatchApproval"))
    end)
    it("returns {decision=declined} for requestUserInput", function()
      assert.same({ decision = "declined" },
        approval._deny_result("item/tool/requestUserInput"))
    end)
    it("returns {decision=declined} for elicitation", function()
      assert.same({ decision = "declined" },
        approval._deny_result("mcpServer/elicitation/request"))
    end)
  end)

  -- ── _get_policy ────────────────────────────────────────────────
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

  -- ── handle() auto-allow ────────────────────────────────────────
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

  -- ── handle() auto-deny ─────────────────────────────────────────
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

  -- ── handle() prompt ────────────────────────────────────────────
  describe("handle() prompt policy", function()
    -- vim.schedule executes immediately in the mock (callback())
    -- vim.fn.confirm returns 1 = Allow (first choice), 2 = Deny (second choice)

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

    it("responds with confirmed when user selects Allow for requestUserInput", function()
      vim.fn.confirm = function() return 1 end
      local result
      approval.handle("item/tool/requestUserInput", {}, function(r) result = r end)
      assert.same({ decision = "confirmed" }, result)
    end)

    it("responds with declined when user denies elicitation", function()
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

    it("is safe when respond is called inside vim.schedule", function()
      -- vim.schedule executes callback immediately in mock; verify no errors
      vim.fn.confirm = function() return 1 end
      assert.has_no.errors(function()
        approval.handle("item/commandExecution/requestApproval", {}, function() end)
      end)
    end)
  end)

  -- ── APPROVAL_METHODS list ──────────────────────────────────────
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
```

- [ ] **Step 2: Run tests to verify they fail**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | grep -E "approval_spec|Error" | head -20
```

Expected: errors about missing module `codex.handlers.approval`

- [ ] **Step 3: Implement lua/codex/handlers/approval.lua**

```lua
-- lua/codex/handlers/approval.lua
local M = {}

M.APPROVAL_METHODS = {
  "item/commandExecution/requestApproval",
  "item/permissions/requestApproval",
  "item/fileChange/requestApproval",
  "applyPatchApproval",
  "item/tool/requestUserInput",
  "mcpServer/elicitation/request",
}

local function is_user_input(method)
  return method:find("requestUserInput", 1, true) ~= nil
    or method:find("elicitation", 1, true) ~= nil
end

function M._approve_result(method)
  if is_user_input(method) then
    return { decision = "confirmed" }
  end
  return { decision = "approved" }
end

function M._deny_result(method)
  if is_user_input(method) then
    return { decision = "declined" }
  end
  return { decision = "denied" }
end

function M._get_policy()
  local ok, init = pcall(require, "codex.init")
  if ok and init.state and init.state.config and init.state.config.approval then
    return init.state.config.approval.policy or "prompt"
  end
  return "prompt"
end

function M._prompt_user(method, params, respond)
  vim.schedule(function()
    local label = (params and (params.description or params.command or params.tool))
      or method
    local answer = vim.fn.confirm("codex: Allow " .. label .. "?", "&Allow\n&Deny", 2)
    if answer == 1 then
      respond(M._approve_result(method), nil)
    else
      respond(M._deny_result(method), nil)
    end
  end)
end

function M.handle(method, params, respond)
  local policy = M._get_policy()
  if policy == "auto-allow" then
    respond(M._approve_result(method), nil)
  elseif policy == "auto-deny" then
    respond(M._deny_result(method), nil)
  else
    M._prompt_user(method, params, respond)
  end
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | tail -5
```

Expected: all 306 + new approval tests pass.

- [ ] **Step 5: Commit**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git add lua/codex/handlers/approval.lua tests/unit/approval_spec.lua
git commit -m "feat(phase5): add handlers/approval.lua — policy-based approval with prompt/auto-allow/auto-deny"
```

---

## Task 2: Wire approval into handlers/init.lua and app_server.lua

**Files:**
- Modify: `lua/codex/handlers/init.lua` (register approval methods in `setup()`)
- Modify: `lua/codex/app_server.lua` (replace hard-coded deny with `approval.handle()`)
- Modify: `tests/unit/diff_apply_spec.lua` (verify approval methods are registered)

- [ ] **Step 1: Read current lua/codex/handlers/init.lua**

Read the file to see the exact current `setup()` function.

- [ ] **Step 2: Extend setup() in handlers/init.lua**

Find:
```lua
function M.setup()
  if _setup_done then return end
  _setup_done = true
  local diff_apply = require("codex.handlers.diff_apply")
  M.register("$/codex/fileChange", diff_apply)
end
```

Replace with:
```lua
function M.setup()
  if _setup_done then return end
  _setup_done = true

  local diff_apply = require("codex.handlers.diff_apply")
  M.register("$/codex/fileChange", diff_apply)

  local approval = require("codex.handlers.approval")
  for _, method in ipairs(approval.APPROVAL_METHODS) do
    local m = method
    M.register(m, {
      on_request = function(params, respond)
        approval.handle(m, params, respond)
      end,
    })
  end
end
```

- [ ] **Step 3: Modify app_server.lua to route approvals through the handler**

Read `lua/codex/app_server.lua` to find `ensure_respond_to_server_request`.

Find:
```lua
local function ensure_respond_to_server_request(method, params, respond)
    if method == "item/commandExecution/requestApproval" or method == "item/permissions/requestApproval" then
        respond({ decision = "denied" })
    elseif method == "item/fileChange/requestApproval" or method == "applyPatchApproval" then
        respond({ decision = "denied" })
    elseif method == "item/tool/requestUserInput" or method == "mcpServer/elicitation/request" then
        respond({ decision = "declined" })
    else
        respond(nil, { code = -32601, message = "Method not found: " .. tostring(method) })
    end
end
```

Replace with:
```lua
local function ensure_respond_to_server_request(method, params, respond)
    local ok, approval = pcall(require, "codex.handlers.approval")
    if ok and approval.handle then
        approval.handle(method, params, respond)
    elseif method:find("requestUserInput", 1, true) or method:find("elicitation", 1, true) then
        respond({ decision = "declined" })
    elseif method:find("requestApproval", 1, true) or method == "applyPatchApproval" then
        respond({ decision = "denied" })
    else
        respond(nil, { code = -32601, message = "Method not found: " .. tostring(method) })
    end
end
```

- [ ] **Step 4: Add test for approval registration in diff_apply_spec.lua**

Read `tests/unit/diff_apply_spec.lua` to find the correct location.

Add this describe block inside the outermost `describe("codex.handlers", ...)` block, after the existing `describe("handlers/init.lua", ...)` block:

```lua
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
```

- [ ] **Step 5: Run all tests**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | tail -5
```

Expected: all tests pass (306 + approval tests + new registration tests).

- [ ] **Step 6: Commit**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git add lua/codex/handlers/init.lua lua/codex/app_server.lua tests/unit/diff_apply_spec.lua
git commit -m "feat(phase5): wire approval handler into init.lua dispatcher + app_server.lua"
```

- [ ] **Step 7: Tag phase-5-complete**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git tag phase-5-complete
```

---

## Verification

```bash
# All tests pass
make test-unit

# Headless: verify approval handler loads without error
nvim --headless \
  -u NORC --cmd "set rtp+=$(pwd)" \
  -c "lua local a = require('codex.handlers.approval'); print('policy:', a._get_policy())" \
  -c "qa" 2>&1
```

Expected: `policy: prompt`
