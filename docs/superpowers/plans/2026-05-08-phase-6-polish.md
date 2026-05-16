# Phase 6: Logger + Auto-restart + Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured logging, auto-restart with exponential backoff when the app-server crashes, implement the `:CodexSelectModel` command, and write PROTOCOL/ARCHITECTURE/README docs.

**Architecture:** `logger.lua` is a thin level-filtered `vim.notify` wrapper consumed across modules. Auto-restart adds state to `app_server.lua`'s `on_exit` handler. `:CodexSelectModel` uses `vim.ui.select` with the user-configured `models` list. Docs are static markdown files.

**Tech Stack:** Pure Lua, `vim.notify`, `vim.ui.select`, `vim.defer_fn`, busted (Lua 5.1).

---

## File Map

| File | Role |
|------|------|
| `lua/codex/logger.lua` | Level-filtered logger; wraps `vim.notify` |
| `lua/codex/app_server.lua` | Modified: exponential-backoff auto-restart in `on_exit` |
| `lua/codex/init.lua` | Modified: real `:CodexSelectModel` command |
| `tests/unit/logger_spec.lua` | Tests for level filtering and message format |
| `tests/unit/init_spec.lua` | Extended: CodexSelectModel tests |
| `PROTOCOL.md` | Known codex app-server RPC methods |
| `ARCHITECTURE.md` | Module dependency diagram + data-flow description |
| `README.md` | Updated: installation, quickstart, config reference, migration guide |

---

## Task 1: logger.lua — structured level-filtered logging

**Files:**
- Create: `lua/codex/logger.lua`
- Create: `tests/unit/logger_spec.lua`

- [ ] **Step 1: Write failing tests**

```lua
-- tests/unit/logger_spec.lua
require("busted_setup")

describe("codex.logger", function()
  local logger
  local notify_calls

  before_each(function()
    package.loaded["codex.logger"] = nil
    notify_calls = {}
    vim.notify = function(msg, level, opts)
      table.insert(notify_calls, { msg = msg, level = level, opts = opts })
    end
    logger = require("codex.logger")
  end)

  -- ── set_level ──────────────────────────────────────────────────
  describe("set_level()", function()
    it("accepts numeric level", function()
      logger.set_level(vim.log.levels.WARN)
      assert.equals(vim.log.levels.WARN, logger.level)
    end)

    it("accepts string 'warn'", function()
      logger.set_level("warn")
      assert.equals(vim.log.levels.WARN, logger.level)
    end)

    it("accepts string 'error'", function()
      logger.set_level("error")
      assert.equals(vim.log.levels.ERROR, logger.level)
    end)

    it("accepts string 'info'", function()
      logger.set_level("info")
      assert.equals(vim.log.levels.INFO, logger.level)
    end)

    it("accepts string 'debug'", function()
      logger.set_level("debug")
      assert.equals(vim.log.levels.DEBUG, logger.level)
    end)

    it("accepts string 'trace'", function()
      logger.set_level("trace")
      assert.equals(0, logger.level)
    end)
  end)

  -- ── level filtering ────────────────────────────────────────────
  describe("level filtering", function()
    it("default level filters out debug messages", function()
      -- default level is WARN
      logger.debug("should be filtered")
      assert.equals(0, #notify_calls)
    end)

    it("default level shows warn messages", function()
      logger.warn("visible warning")
      assert.equals(1, #notify_calls)
    end)

    it("default level shows error messages", function()
      logger.error("visible error")
      assert.equals(1, #notify_calls)
    end)

    it("after set_level('debug'), debug messages are shown", function()
      logger.set_level("debug")
      logger.debug("now visible")
      assert.equals(1, #notify_calls)
    end)

    it("after set_level('error'), warn messages are filtered", function()
      logger.set_level("error")
      logger.warn("should be filtered")
      assert.equals(0, #notify_calls)
    end)

    it("after set_level('trace'), all messages are shown", function()
      logger.set_level("trace")
      logger.trace("trace msg")
      logger.debug("debug msg")
      logger.info("info msg")
      logger.warn("warn msg")
      logger.error("error msg")
      assert.equals(5, #notify_calls)
    end)
  end)

  -- ── message format ─────────────────────────────────────────────
  describe("message format", function()
    before_each(function()
      logger.set_level("trace")
    end)

    it("warn message contains the input string", function()
      logger.warn("test warning")
      assert.is_truthy(notify_calls[1].msg:find("test warning", 1, true))
    end)

    it("error message contains the input string", function()
      logger.error("test error")
      assert.is_truthy(notify_calls[1].msg:find("test error", 1, true))
    end)

    it("passes correct log level to vim.notify for warn", function()
      logger.warn("w")
      assert.equals(vim.log.levels.WARN, notify_calls[1].level)
    end)

    it("passes correct log level to vim.notify for error", function()
      logger.error("e")
      assert.equals(vim.log.levels.ERROR, notify_calls[1].level)
    end)

    it("passes correct log level to vim.notify for info", function()
      logger.info("i")
      assert.equals(vim.log.levels.INFO, notify_calls[1].level)
    end)

    it("passes title=codex.nvim in opts", function()
      logger.warn("w")
      assert.equals("codex.nvim", notify_calls[1].opts and notify_calls[1].opts.title)
    end)
  end)

  -- ── per-function level correctness ────────────────────────────
  describe("per-function levels", function()
    before_each(function()
      logger.set_level("trace")
    end)

    it("trace() passes level 0", function()
      logger.trace("t")
      assert.equals(0, notify_calls[1].level)
    end)

    it("debug() passes vim.log.levels.DEBUG", function()
      logger.debug("d")
      assert.equals(vim.log.levels.DEBUG, notify_calls[1].level)
    end)
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | grep -E "logger_spec|Error" | head -10
```

Expected: errors about missing module `codex.logger`

- [ ] **Step 3: Implement lua/codex/logger.lua**

```lua
-- lua/codex/logger.lua
local M = {}

M.level = vim.log.levels.WARN

local STR_TO_LEVEL = {
  trace = 0,
  debug = vim.log.levels.DEBUG,
  info  = vim.log.levels.INFO,
  warn  = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

function M.set_level(level)
  if type(level) == "string" then
    M.level = STR_TO_LEVEL[level] or vim.log.levels.WARN
  else
    M.level = level
  end
end

local function log(num_level, msg)
  if num_level < M.level then return end
  vim.notify("[codex] " .. tostring(msg), num_level, { title = "codex.nvim" })
end

function M.trace(msg) log(0,                       msg) end
function M.debug(msg) log(vim.log.levels.DEBUG,    msg) end
function M.info(msg)  log(vim.log.levels.INFO,     msg) end
function M.warn(msg)  log(vim.log.levels.WARN,     msg) end
function M.error(msg) log(vim.log.levels.ERROR,    msg) end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | tail -5
```

Expected: all previous + new logger tests pass.

- [ ] **Step 5: Commit**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git add lua/codex/logger.lua tests/unit/logger_spec.lua
git commit -m "feat(phase6): add logger.lua — level-filtered vim.notify wrapper"
```

---

## Task 2: app_server.lua auto-restart with exponential backoff

**Files:**
- Modify: `lua/codex/app_server.lua`
- (No separate test file — backoff math is verified via exposed state; integration is tested headless)

This task adds an auto-restart mechanism: when the app-server process exits unexpectedly (no pending waiters), it schedules a restart with 2s×2^(attempt-1) delay, capped at 30s, max 5 attempts. The counter resets when a connection succeeds.

- [ ] **Step 1: Read lua/codex/app_server.lua**

Read the file to find `on_exit`, `flush_waiters`, and the module's `state` table.

- [ ] **Step 2: Add restart state and logic**

After `local state = { ... }` (around line 22), add:

```lua
local _restart = {
  attempts   = 0,
  max        = 5,
  base_ms    = 2000,
  enabled    = true,
  timer      = nil,
}
```

Add this helper function after `flush_waiters`:

```lua
local function schedule_restart()
  if not _restart.enabled then return end
  if _restart.attempts >= _restart.max then return end
  _restart.attempts = _restart.attempts + 1
  local delay = math.min(_restart.base_ms * (2 ^ (_restart.attempts - 1)), 30000)
  _restart.timer = vim.defer_fn(function()
    _restart.timer = nil
    if not state.job_id and _restart.enabled then
      M.ensure(function() end)
    end
  end, delay)
end
```

In the `on_exit` handler inside `start_process`, find:
```lua
        on_exit = function(_, code)
            state.job_id = nil
            state.connecting = false
            state.rpc = nil
            state.initialized = false
            if #state.waiters > 0 then
                local stderr = table.concat(state.stderr, "\n")
                flush_waiters(stderr ~= "" and stderr or ("app-server exited with code " .. tostring(code)))
            end
        end,
```

Replace with:
```lua
        on_exit = function(_, code)
            state.job_id = nil
            state.connecting = false
            state.rpc = nil
            state.initialized = false
            if #state.waiters > 0 then
                local stderr = table.concat(state.stderr, "\n")
                flush_waiters(stderr ~= "" and stderr or ("app-server exited with code " .. tostring(code)))
            else
                schedule_restart()
            end
        end,
```

In `flush_waiters`, reset the attempts counter on successful connection. Find:
```lua
local function flush_waiters(err)
    local waiters = state.waiters
    state.waiters = {}
    for _, waiter in ipairs(waiters) do
        waiter(state.rpc, err)
    end
end
```

Replace with:
```lua
local function flush_waiters(err)
    local waiters = state.waiters
    state.waiters = {}
    if not err then
        _restart.attempts = 0
    end
    for _, waiter in ipairs(waiters) do
        waiter(state.rpc, err)
    end
end
```

Also expose state for introspection (add before `return M`):

```lua
function M._restart_state()
  return _restart
end
```

Update `M.stop()` to cancel any pending restart timer and disable auto-restart:

Find the existing `function M.stop()` body. After `state.waiters = {}`, add:
```lua
    _restart.enabled = false
    _restart.attempts = 0
    if _restart.timer then
      -- timer is a handle from vim.defer_fn; we can't cancel it, but disabling
      -- _restart.enabled prevents the callback from starting a new process
      _restart.timer = nil
    end
```

And add re-enabling when `M.ensure()` is called explicitly again. At the top of `M.ensure()`, add:
```lua
    _restart.enabled = true
```

- [ ] **Step 3: Run all tests**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | tail -5
```

Expected: all tests still pass (the change is additive).

- [ ] **Step 4: Commit**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git add lua/codex/app_server.lua
git commit -m "feat(phase6): auto-restart app-server with exponential backoff (max 5 attempts)"
```

---

## Task 3: CodexSelectModel command + documentation

**Files:**
- Modify: `lua/codex/init.lua` — real `:CodexSelectModel` implementation
- Modify: `tests/unit/init_spec.lua` — tests for CodexSelectModel
- Create: `PROTOCOL.md`
- Create: `ARCHITECTURE.md`
- Modify: `README.md`

### Sub-task 3a: CodexSelectModel

- [ ] **Step 1: Add vim.ui.select stub to init_spec.lua before_each**

Read `tests/unit/init_spec.lua` to find the shared `before_each` block. Add `vim.ui = { select = function(items, opts, cb) vim._ui_select = { items = items, opts = opts, cb = cb } end }` to the `before_each` (or as a local variable — check what's already there).

- [ ] **Step 2: Add CodexSelectModel tests to tests/unit/init_spec.lua**

Read the file to find the correct insertion point (after the `CodexDiffDeny command` describe block).

Add:
```lua
  describe("CodexSelectModel command", function()
    before_each(function()
      vim.ui = {
        select = function(items, opts, cb)
          vim._ui_select = { items = items, opts = opts, cb = cb }
        end,
      }
      vim._ui_select = nil
    end)

    it("notifies when no models are configured", function()
      codex.setup({ models = {} })
      local notified = false
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then notified = true end
      end
      registered_cmds["CodexSelectModel"].cb({})
      assert.is_true(notified)
    end)

    it("calls vim.ui.select with model names", function()
      codex.setup({ models = {
        { name = "GPT-4o", value = "gpt-4o" },
        { name = "o1",     value = "o1" },
      }})
      registered_cmds["CodexSelectModel"].cb({})
      assert.is_not_nil(vim._ui_select)
      assert.same({ "GPT-4o", "o1" }, vim._ui_select.items)
    end)

    it("sets state.selected_model after selection", function()
      codex.setup({ models = {
        { name = "GPT-4o", value = "gpt-4o" },
      }})
      registered_cmds["CodexSelectModel"].cb({})
      assert.is_not_nil(vim._ui_select)
      vim._ui_select.cb("GPT-4o", 1)  -- simulate user picking first item
      assert.equals("gpt-4o", codex.state.selected_model)
    end)

    it("does nothing when user cancels (nil choice)", function()
      codex.setup({ models = {
        { name = "GPT-4o", value = "gpt-4o" },
      }})
      codex.state.selected_model = nil
      registered_cmds["CodexSelectModel"].cb({})
      vim._ui_select.cb(nil, nil)
      assert.is_nil(codex.state.selected_model)
    end)
  end)
```

- [ ] **Step 3: Run tests to verify new tests fail**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | grep -E "FAIL|CodexSelectModel" | head -10
```

Expected: failures for the new CodexSelectModel tests (stub notify in place).

- [ ] **Step 4: Replace CodexSelectModel stub in lua/codex/init.lua**

Read `lua/codex/init.lua` to find the stub:
```lua
  vim.api.nvim_create_user_command("CodexSelectModel", function()
    vim.notify("CodexSelectModel: implemented in Phase 6", vim.log.levels.INFO)
  end, { desc = "Select Codex model" })
```

Replace with:
```lua
  vim.api.nvim_create_user_command("CodexSelectModel", function()
    local models = (M.state.config and M.state.config.models) or {}
    if #models == 0 then
      vim.notify("codex: no models configured — add models = {...} to setup()", vim.log.levels.WARN)
      return
    end
    local names = {}
    for _, m in ipairs(models) do
      names[#names + 1] = m.name or m.value or tostring(m)
    end
    vim.ui.select(names, { prompt = "Select Codex model:" }, function(choice, idx)
      if not choice then return end
      local model = models[idx]
      M.state.selected_model = model.value or model.name
      vim.notify("codex: model set to " .. choice, vim.log.levels.INFO)
    end)
  end, { desc = "Select Codex model" })
```

Also add `selected_model = nil` to `M.state` initial table:

Find:
```lua
M.state = {
  config = nil,
  rpc = nil,
  port = nil,
  initialized = false,
  mention_queue = {},
  mention_timer = nil,
  connection_timer = nil,
}
```

Replace with:
```lua
M.state = {
  config = nil,
  rpc = nil,
  port = nil,
  initialized = false,
  mention_queue = {},
  mention_timer = nil,
  connection_timer = nil,
  selected_model = nil,
}
```

- [ ] **Step 5: Run tests to verify CodexSelectModel tests pass**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 6: Commit CodexSelectModel**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git add lua/codex/init.lua tests/unit/init_spec.lua
git commit -m "feat(phase6): implement CodexSelectModel command with vim.ui.select"
```

### Sub-task 3b: Documentation

- [ ] **Step 7: Create PROTOCOL.md**

Create `PROTOCOL.md` at the repo root with:

```markdown
# Codex App-Server Protocol Notes

> These notes are derived from reverse-engineering codex CLI v0.x. Protocol may change.
> Plugin compatibility: tested against codex ≥ 0.1.0.

## Connection

The plugin spawns `codex app-server --listen ws://127.0.0.1:<PORT>` and connects
via WebSocket. All messages are JSON-RPC 2.0.

## Initialization handshake

After the WS connection is open, the client sends:

```json
{ "jsonrpc": "2.0", "id": 1, "method": "initialize",
  "params": { "clientInfo": { "name": "codex.nvim", "version": "0.1.0" },
              "capabilities": { "experimentalApi": true } } }
```

Server responds with `result: {}`. Client then sends notification:

```json
{ "jsonrpc": "2.0", "method": "initialized" }
```

## Client → Server requests

| Method | Params | Description |
|--------|--------|-------------|
| `initialize` | `clientInfo`, `capabilities` | Required handshake |
| `thread/start` | `cwd`, `sandbox`, `approvalPolicy`, `model` | Create a new thread |
| `turn/start` | `threadId`, `cwd`, `input[{type,text}]`, `approvalPolicy` | Send a prompt |

## Server → Client notifications

| Method | Key params | Description |
|--------|------------|-------------|
| `turn/started` | `turn.id` | Turn began |
| `turn/completed` | `threadId`, `turnId` | Turn finished |
| `item/started` | `item.type` | Work item started (command, file change, …) |
| `item/agentMessage/delta` | `delta` | Streamed agent text |
| `item/plan/delta` | `delta` | Streamed plan text |
| `item/reasoning/summaryTextDelta` | `delta` | Reasoning summary |
| `item/fileChange/patchUpdated` | `patch` | Unified diff for a file change |
| `error` | `message` | Server-side error |

## Server → Client requests (approval)

The server may send RPC **requests** (with id) that require a response:

| Method | Response format | Description |
|--------|-----------------|-------------|
| `item/commandExecution/requestApproval` | `{ decision: "approved" \| "denied" }` | Run a shell command |
| `item/permissions/requestApproval` | `{ decision: "approved" \| "denied" }` | Expand permissions |
| `item/fileChange/requestApproval` | `{ decision: "approved" \| "denied" }` | Apply a file patch |
| `applyPatchApproval` | `{ decision: "approved" \| "denied" }` | Alternative patch approval |
| `item/tool/requestUserInput` | `{ decision: "confirmed" \| "declined" }` | User input required |
| `mcpServer/elicitation/request` | `{ decision: "confirmed" \| "declined" }` | MCP elicitation |

## Context notifications (Neovim → Server)

The plugin sends these notifications to provide editor context:

| Method | Params | Description |
|--------|--------|-------------|
| `$/codex/mention` | `{ text: "file.lua:1-20" }` | Add a file/range to context |
| `$/codex/selectionChanged` | `{ filePath, text, start, end }` | Cursor/selection update |
| `$/codex/fileChange` | `{ patch }` | File change notification (may also arrive server→client) |
```

- [ ] **Step 8: Create ARCHITECTURE.md**

Create `ARCHITECTURE.md` at the repo root with:

```markdown
# codex.nvim Architecture

## Module dependency graph

```
plugin/codex.lua
  └─▶ codex.init (setup, commands, mention queue)
        ├─▶ codex.config         (defaults + validation)
        ├─▶ codex.terminal       (provider abstraction)
        │     ├─▶ terminal.native
        │     ├─▶ terminal.snacks
        │     └─▶ terminal.external
        ├─▶ codex.selection      (cursor/selection tracking, 50ms debounce)
        ├─▶ codex.visual_commands (range command helpers)
        ├─▶ codex.app_server     (process lifecycle, WebSocket client)
        │     └─▶ codex.rpc      (JSON-RPC 2.0 over WebSocket)
        │           └─▶ codex.transport (WebSocket framing)
        └─▶ codex.handlers.init  (method dispatcher)
              ├─▶ handlers.diff_apply  ─▶ codex.diff
              └─▶ handlers.approval
```

## Data flows

### User sends a prompt (`:Codex`)

1. `terminal.simple_toggle()` opens the terminal split
2. Codex CLI TUI runs inside the terminal; user types there

### File-range mention (`:CodexAdd file.lua 10 20`)

1. `init.enqueue_mention("file.lua:10-20")` queues the text
2. If connected: 50ms debounce → `rpc:notify("$/codex/mention", {text=...})`
3. If not connected: queued with 5s expiry; flushed on connection

### Diff approval flow

```
codex app-server
  ──── request: $/codex/fileChange ────▶ handlers.init.handle_request()
                                              │
                                       handlers.diff_apply.on_request()
                                              │
                                       diff.open(patch, respond_fn, opts)
                                              │
                               [User sees split diff buffer]
                                              │
                             `:CodexDiffAccept` or `:CodexDiffDeny`
                                              │
                               diff.accept_all() / diff.deny_all()
                                              │
                               respond_fn({accepted, patch})
  ◀──── response ──────────────────────────────
```

### Approval flow (shell command, file change, etc.)

```
codex app-server
  ──── request: item/.../requestApproval ──▶ handlers.approval.handle()
                                                  │
                                    [policy=prompt: vim.fn.confirm dialog]
                                    [policy=auto-allow: immediate approve]
                                    [policy=auto-deny:  immediate deny]
                                                  │
                               respond({decision: "approved"|"denied"})
  ◀──── response ──────────────────────────────────
```

## Key design decisions

- **Pure Lua, zero runtime dependencies** — no plenary, no nui
- **Two WebSocket connections** — `app_server.lua` manages process lifecycle and the initialization handshake; `init.lua` creates a second connection for editor-context notifications and diff/approval handlers
- **Handlers dispatcher** — `handlers/init.lua` provides a registry so new RPC methods can be added without touching `init.lua`
- **Hunk-level diff review** — `diff.lua` provides per-hunk accept/reject with `[ACCEPT]`/`[REJECT]` markers, unlike simple whole-file diff approaches
- **50ms selection debounce** — prevents flooding the app-server with cursor-move events
```

- [ ] **Step 9: Update README.md**

Read the current `README.md` to understand its structure, then update it. The README must contain:
1. Header + one-line description
2. Prerequisites (Neovim ≥ 0.9, codex CLI installed)
3. Installation (lazy.nvim snippet)
4. Quickstart (minimal setup call + keymaps)
5. Configuration reference (full defaults table with comments)
6. Commands table
7. Migration guide (old commands → new commands)

Write the complete README:

```markdown
# codex.nvim

Neovim integration for [OpenAI Codex CLI](https://github.com/openai/codex).
Mirrors the [claudecode.nvim](https://github.com/coder/claudecode.nvim) interface so
switching between AI assistants feels seamless.

## Prerequisites

- Neovim ≥ 0.9
- `codex` CLI installed and in `$PATH` (`npm install -g @openai/codex` or equivalent)

## Installation

```lua
-- lazy.nvim
{
  "your-username/codex.nvim",
  config = function()
    require("codex").setup()
  end,
}
```

## Quickstart

```lua
require("codex").setup({
  auto_start = true,
  approval = { policy = "prompt" },  -- ask before running commands
})

-- Recommended keymaps (mirrors claudecode.nvim)
local map = vim.keymap.set
map("n", "<leader>aa", "<cmd>Codex<cr>",          { desc = "Toggle Codex" })
map("n", "<leader>ar", "<cmd>Codex --resume<cr>", { desc = "Resume Codex" })
map("n", "<leader>af", "<cmd>CodexFocus<cr>",     { desc = "Focus Codex" })
map({ "n", "v" }, "<leader>as", "<cmd>CodexSend<cr>", { desc = "Send to Codex" })
```

## Configuration

```lua
require("codex").setup({
  -- Process
  auto_start           = true,          -- start app-server on setup()
  codex_cmd            = "codex",       -- path to the codex binary
  env                  = {},            -- extra environment variables
  log_level            = "warn",        -- "trace"|"debug"|"info"|"warn"|"error"

  -- Port
  port_range           = { min = 10000, max = 65535 },

  -- Selection tracking
  track_selection      = true,          -- send cursor/selection to codex
  visual_demotion_delay_ms = 50,        -- ms before visual → cursor after mode change
  focus_after_send     = false,         -- focus terminal after CodexSend

  -- Connection
  connection_wait_delay  = 600,         -- ms to wait before first connect attempt
  connection_timeout     = 10000,       -- ms total connection timeout
  queue_timeout          = 5000,        -- ms mention queue item TTL

  -- Diff viewer
  diff_opts = {
    layout              = "vertical",   -- "vertical"|"horizontal"
    open_in_new_tab     = false,
    keep_terminal_focus = false,
    on_new_file_reject  = "keep_empty",
    hunk_level_review   = true,         -- per-hunk accept/reject (codex-specific)
  },

  -- Terminal
  terminal = {
    provider            = "auto",       -- "auto"|"snacks"|"native"|"external"|"none"
    split_side          = "right",
    split_width_percentage = 0.30,
    snacks_win_opts     = {},
    auto_close          = true,
    cwd_provider        = nil,
    git_repo_cwd        = true,
    provider_opts       = { external_terminal_cmd = nil },
  },

  -- Approval (codex-specific)
  approval = {
    policy   = "prompt",              -- "prompt"|"auto-deny"|"auto-allow"
    sandbox  = "workspace-write",
  },

  -- Model list for CodexSelectModel
  models = {
    -- { name = "GPT-4o", value = "gpt-4o" },
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Codex` | Toggle Codex terminal panel |
| `:Codex --resume` | Resume last session |
| `:Codex --continue` | Continue last session |
| `:CodexFocus` | Smart focus/unfocus panel |
| `:CodexOpen` | Open panel |
| `:CodexClose` | Close panel |
| `:CodexAdd <file> [start] [end]` | Add file/range to context |
| `:CodexSend` | Send visual selection to Codex |
| `:CodexDiffAccept` | Accept pending diff |
| `:CodexDiffDeny` | Deny pending diff |
| `:CodexSelectModel` | Pick from configured models |
| `:CodexStart` | Start app-server manually |
| `:CodexStop` | Stop app-server |
| `:CodexStatus` | Show connection status |

### Diff buffer keymaps (active when a diff is shown)

| Key | Action |
|-----|--------|
| `a` | Accept hunk at cursor |
| `r` | Reject hunk at cursor |
| `A` / `<CR>` | Accept all hunks |
| `R` / `q` | Reject all hunks |
| `n` | Next hunk |
| `p` | Previous hunk |

## Migration from old codex.nvim

| Old command | New command |
|-------------|-------------|
| `:CodexCLI` / `:CodexCLIToggle` | `:Codex` |
| `:CodexToggle` | `:Codex` |
| `:CodexResume` | `:Codex --resume` |
| `:CodexDiff` / `:CodexDiffToggle` | Diff opens automatically; use `:CodexDiffAccept`/`:CodexDiffDeny` |
| `:CodexApply` | `:CodexDiffAccept` |

## License

MIT
```

- [ ] **Step 10: Run all tests**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | tail -5
```

Expected: all tests pass (no regressions from doc/init changes).

- [ ] **Step 11: Commit documentation + CodexSelectModel**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git add PROTOCOL.md ARCHITECTURE.md README.md
git commit -m "docs(phase6): add PROTOCOL.md, ARCHITECTURE.md; update README with full config reference"
```

- [ ] **Step 12: Tag phase-6-complete**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git tag phase-6-complete
```

---

## Verification

```bash
# All tests pass
make test-unit

# Headless: verify logger loads
nvim --headless -u NORC --cmd "set rtp+=$(pwd)" \
  -c "lua local l = require('codex.logger'); l.warn('ok'); print('logger: ok')" \
  -c "qa" 2>&1

# Headless: verify CodexSelectModel registered
nvim --headless -u NORC --cmd "set rtp+=$(pwd)" \
  -c "lua require('codex').setup({ auto_start=false, models={{name='GPT-4o',value='gpt-4o'}} })" \
  -c "lua print('select_model cmd:', tostring(vim.api.nvim_get_commands({})['CodexSelectModel'] ~= nil))" \
  -c "qa" 2>&1
```
