# Remote TUI Connection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `:Codex` open `codex --remote <app-server-url>` so the TUI connects to the plugin's app-server, enabling `applyPatchApproval` → diff UI flow.

**Architecture:** `app_server.ensure()` is called before opening the terminal; when ready the URL is passed as `--remote` to the codex CLI. `terminal.lua` gains an optional `cmd_override` parameter so callers can supply a full command string. `flush_mentions` uses the same URL when it must open the terminal for `@mention` injection.

**Tech Stack:** Lua, Neovim API, busted test framework (existing)

---

## File Map

| File | Change |
|------|--------|
| `lua/codex/terminal.lua` | Add `cmd_override` param to `open`, `simple_toggle`, `focus_toggle` |
| `lua/codex/init.lua` | Add `build_codex_cmd()`, rewrite `:Codex` command, update `flush_mentions` |
| `tests/unit/init_spec.lua` | Update stale tests (`_open_flag`, stale commands list), add new behaviour tests |

---

## Task 1: Add `cmd_override` to `terminal.lua`

**Files:**
- Modify: `lua/codex/terminal.lua:67-85`
- Test: `tests/unit/terminal_spec.lua` (create if not exists)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/terminal_spec.lua`:

```lua
require("busted_setup")

describe("codex.terminal", function()
  local terminal
  local last_open_cmd, last_toggle_cmd, last_focus_cmd

  before_each(function()
    package.loaded["codex.terminal"] = nil
    for _, m in ipairs({ "codex.terminal.native", "codex.terminal.snacks", "codex.terminal.external" }) do
      package.loaded[m] = nil
    end

    local fake_provider = {
      is_available = function() return true end,
      open         = function(cmd) last_open_cmd   = cmd end,
      simple_toggle= function(cmd) last_toggle_cmd = cmd end,
      focus_toggle = function(cmd) last_focus_cmd  = cmd end,
      close        = function() end,
      get_active_bufnr = function() return nil end,
    }
    package.preload["codex.terminal.native"] = function() return fake_provider end
    package.preload["codex.terminal.snacks"] = function()
      return { is_available = function() return false end }
    end

    terminal = require("codex.terminal")
    terminal.setup({ codex_cmd = "codex", terminal = { provider = "native" } })
    last_open_cmd, last_toggle_cmd, last_focus_cmd = nil, nil, nil
  end)

  after_each(function()
    for _, m in ipairs({ "codex.terminal", "codex.terminal.native", "codex.terminal.snacks", "codex.terminal.external" }) do
      package.loaded[m] = nil
      package.preload[m] = nil
    end
  end)

  it("open() without override uses codex_cmd", function()
    terminal.open()
    assert.equals("codex", last_open_cmd)
  end)

  it("open(cmd_override) uses override", function()
    terminal.open("codex --remote ws://127.0.0.1:9999")
    assert.equals("codex --remote ws://127.0.0.1:9999", last_open_cmd)
  end)

  it("simple_toggle() without override uses codex_cmd", function()
    terminal.simple_toggle()
    assert.equals("codex", last_toggle_cmd)
  end)

  it("simple_toggle(cmd_override) uses override", function()
    terminal.simple_toggle("codex --remote ws://127.0.0.1:9999")
    assert.equals("codex --remote ws://127.0.0.1:9999", last_toggle_cmd)
  end)

  it("focus_toggle() without override uses codex_cmd", function()
    terminal.focus_toggle()
    assert.equals("codex", last_focus_cmd)
  end)

  it("focus_toggle(cmd_override) uses override", function()
    terminal.focus_toggle("codex --remote ws://127.0.0.1:9999")
    assert.equals("codex --remote ws://127.0.0.1:9999", last_focus_cmd)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
nvim --headless -u tests/minimal_init.lua \
  -c 'lua require("busted").run()' \
  -c 'PlenaryBustedFile tests/unit/terminal_spec.lua'
```

Expected: FAIL — `open(cmd_override)` passes `"codex"` instead of the override.

- [ ] **Step 3: Implement cmd_override in terminal.lua**

Edit `lua/codex/terminal.lua`, replace lines 67–85:

```lua
function M.open(cmd_override)
  if not active_provider then return end
  active_provider.open(cmd_override or get_cmd(), get_opts())
end

function M.close()
  if not active_provider then return end
  active_provider.close()
end

function M.simple_toggle(cmd_override)
  if not active_provider then return end
  active_provider.simple_toggle(cmd_override or get_cmd(), get_opts())
end

function M.focus_toggle(cmd_override)
  if not active_provider then return end
  active_provider.focus_toggle(cmd_override or get_cmd(), get_opts())
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedFile tests/unit/terminal_spec.lua'
```

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/terminal.lua tests/unit/terminal_spec.lua
git commit -m "feat: add cmd_override param to terminal open/simple_toggle/focus_toggle"
```

---

## Task 2: Add `build_codex_cmd` + rewrite `:Codex` command

**Files:**
- Modify: `lua/codex/init.lua:19-48` (flush_mentions), `lua/codex/init.lua:91-99` (:Codex command)
- Test: `tests/unit/init_spec.lua`

- [ ] **Step 1: Write the failing tests**

Add these test cases to `tests/unit/init_spec.lua` inside the existing `describe("codex.init", ...)` block, after the existing `describe("command registration", ...)` block:

```lua
  describe(":Codex command with --remote", function()
    local open_calls, toggle_calls, ensure_cbs, notified
    local terminal_stub, app_server_stub

    before_each(function()
      open_calls   = {}
      toggle_calls = {}
      ensure_cbs   = {}
      notified     = {}

      terminal_stub = {
        setup    = function() end,
        open     = function(cmd) table.insert(open_calls, cmd) end,
        close    = function() end,
        simple_toggle = function(cmd) table.insert(toggle_calls, cmd) end,
        focus_toggle  = function() end,
        get_active_terminal_bufnr = function() return nil end,
        send_text = function() end,
      }
      app_server_stub = {
        ensure    = function(cb) table.insert(ensure_cbs, cb) end,
        configure = function() end,
        stop      = function() end,
        url       = function() return "ws://127.0.0.1:19999" end,
      }

      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      package.loaded["codex.init"] = nil
      package.preload["codex.terminal"]    = function() return terminal_stub end
      package.preload["codex.app_server"]  = function() return app_server_stub end

      codex = require("codex.init")
      codex.setup({})
    end)

    after_each(function()
      package.preload["codex.terminal"]   = nil
      package.preload["codex.app_server"] = nil
    end)

    it(":Codex toggles existing terminal without calling ensure", function()
      -- simulate terminal already running
      terminal_stub.get_active_terminal_bufnr = function() return 5 end
      registered_cmds["Codex"].cb({ args = "" })
      -- simple_toggle called, ensure NOT called
      assert.equals(1, #toggle_calls)
      assert.equals(0, #ensure_cbs)
    end)

    it(":Codex opens with --remote url when app-server ready", function()
      -- terminal not running; fire the ensure callback immediately
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "" })
      assert.equals(1, #ensure_cbs)
      -- fire the callback (simulating success)
      ensure_cbs[1](nil, nil)
      -- open should have been called with --remote
      assert.equals(1, #open_calls)
      assert.matches("--remote ws://127%.0%.0%.1:19999", open_calls[1])
    end)

    it(":Codex --resume opens with resume --last and --remote", function()
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "--resume" })
      ensure_cbs[1](nil, nil)
      assert.equals(1, #open_calls)
      assert.matches("--remote ws://127%.0%.0%.1:19999", open_calls[1])
      assert.matches("resume", open_calls[1])
      assert.matches("%-%-last", open_calls[1])
    end)

    it(":Codex shows error and does NOT open when app-server fails", function()
      terminal_stub.get_active_terminal_bufnr = function() return nil end
      registered_cmds["Codex"].cb({ args = "" })
      ensure_cbs[1](nil, "connection refused")
      assert.equals(0, #open_calls)
      assert.equals(1, #notified)
      assert.matches("not ready", notified[1].msg)
    end)
  end)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedFile tests/unit/init_spec.lua'
```

Expected: the 4 new tests FAIL.

- [ ] **Step 3: Remove stale tests that will conflict**

In `tests/unit/init_spec.lua`, find and delete these three test cases (they test behaviour we're replacing):

```lua
    it(":Codex --resume sets _open_flag", function()
    it(":Codex --continue sets _open_flag", function()
    it(":Codex with no arg clears _open_flag", function()
```

Also update the `expected_commands` list — remove `"Codexadd"` and `"Codexsend"` (aliases were deleted in a previous commit), and remove `"CodexAdd with just file enqueues file path"` test that passes a file arg (CodexAdd now takes no args):

```lua
    -- Remove these two from expected_commands:
    -- "Codexadd", "Codexsend",

    -- Remove this test:
    -- it(":CodexAdd with just file enqueues file path", function()
```

- [ ] **Step 4: Implement `build_codex_cmd` and rewrite `:Codex` in `init.lua`**

Replace the `flush_mentions` function (lines 19–48) and the `:Codex` command block (lines 91–99) in `lua/codex/init.lua`:

After the `is_connected` function (line 17), add:

```lua
local function build_codex_cmd(flag)
  local base = (M.state.config and M.state.config.codex_cmd) or "codex"
  local url = require("codex.app_server").url()
  if not url then return nil end
  local remote = " --remote " .. url
  if flag == "--resume" or flag == "--continue" then
    return base .. remote .. " resume --last"
  end
  return base .. remote
end
```

Replace `flush_mentions` (lines 19–48):

```lua
local function flush_mentions()
  if #M.state.mention_queue == 0 then
    return
  end
  local terminal = require("codex.terminal")
  local now = vim.loop.now()
  local queue = {}
  for _, item in ipairs(M.state.mention_queue) do
    if item.expires_at > now then
      table.insert(queue, item.text)
    end
  end
  M.state.mention_queue = {}

  if #queue == 0 then return end

  local function send_all()
    for _, text in ipairs(queue) do
      terminal.send_text("@" .. text .. " ")
    end
  end

  if terminal.get_active_terminal_bufnr() then
    send_all()
  else
    local url = require("codex.app_server").url()
    if not url then
      vim.notify("codex: app-server not ready — cannot open terminal for mention", vim.log.levels.WARN)
      return
    end
    local base = (M.state.config and M.state.config.codex_cmd) or "codex"
    terminal.open(base .. " --remote " .. url)
    vim.defer_fn(send_all, 1500)
  end
end
```

Replace the `:Codex` command registration (lines 91–99):

```lua
  vim.api.nvim_create_user_command("Codex", function(args)
    local arg = (args.args or ""):match("^%s*(.-)%s*$")
    if terminal.get_active_terminal_bufnr() then
      terminal.simple_toggle()
      return
    end
    local app_server = require("codex.app_server")
    app_server.ensure(function(_, err)
      if err then
        vim.notify("codex: app-server not ready — " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      vim.schedule(function()
        terminal.open(build_codex_cmd(arg))
      end)
    end)
  end, { nargs = "?", desc = "Toggle Codex panel" })
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedFile tests/unit/init_spec.lua'
```

Expected: all tests PASS (including the 4 new ones).

- [ ] **Step 6: Commit**

```bash
git add lua/codex/init.lua tests/unit/init_spec.lua
git commit -m "feat: open codex TUI with --remote to connect to plugin app-server"
```

---

## Task 3: Update README and ARCHITECTURE docs

**Files:**
- Modify: `README.md`
- Modify: `ARCHITECTURE.md`

- [ ] **Step 1: Update README.md commands table**

In `README.md`, find the Commands section and update `:Codex` description:

```markdown
| `:Codex` | Toggle Codex terminal (connects to plugin app-server via `--remote`) |
| `:Codex --resume` | Resume last session |
| `:Codex --continue` | Continue last session (alias for `--resume`) |
```

Add a note under the Commands section:

```markdown
> **Note:** `:Codex` requires the app-server to be running (`auto_start = true` by default).
> If the app-server is not ready the command shows an error. Use `:CodexStart` to start it manually.
```

- [ ] **Step 2: Update ARCHITECTURE.md data flow**

In `ARCHITECTURE.md`, update the "User sends a prompt" section:

```markdown
### User sends a prompt (`:Codex`)

1. `app_server.ensure()` waits for the app-server to be ready
2. `terminal.open("codex --remote ws://127.0.0.1:<port>")` opens the TUI connected to the app-server
3. User types in the TUI; the TUI routes all model calls and file changes through the app-server
4. File changes arrive as `applyPatchApproval` requests → `handlers.diff_apply.on_request()` → `diff.open()`
5. User runs `:CodexDiffAccept` / `:CodexDiffDeny` → respond `{decision: "approved"|"denied"}` back to app-server
```

- [ ] **Step 3: Commit docs**

```bash
git add README.md ARCHITECTURE.md
git commit -m "docs: update data flow for --remote TUI connection"
```

---

## Task 4: Push and verify

- [ ] **Step 1: Run full test suite**

```bash
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedDirectory tests { minimal_init = "tests/minimal_init.lua" }'
```

Expected: all tests PASS.

- [ ] **Step 2: Push**

```bash
git push origin main
```

- [ ] **Step 3: Manual smoke test**

1. Open Neovim in a project directory
2. Run `:CodexStatus` — should show "connected"
3. Run `:Codex` — terminal should open with `codex --remote ws://127.0.0.1:<port>`
4. Type a prompt that causes a file change
5. Confirm that the Neovim diff UI opens (not the TUI's own approval dialog)
6. Press `A` or `:CodexDiffAccept` — file should be modified
7. Run `:Codex` again — should hide/show the existing terminal (no new process)
8. Run `:Codex --resume` — should open `codex --remote ws://... resume --last`
