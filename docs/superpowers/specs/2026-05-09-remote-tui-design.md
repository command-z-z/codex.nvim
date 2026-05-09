# Design: Connect Codex TUI to Plugin App-Server via --remote

**Date:** 2026-05-09  
**Status:** Approved

## Problem

The plugin starts two completely independent processes:

1. `codex` (TUI) — handles user interaction, modifies files directly, never contacts the app-server
2. `codex app-server --listen ws://...` — waits for RPC connections, never receives file-change requests from the TUI

Because the TUI bypasses the app-server entirely, `applyPatchApproval` requests never reach the plugin's diff handler, so `CodexDiffAccept`/`CodexDiffDeny` never trigger.

## Solution

`codex` supports `--remote <ws://host:port>` which connects the TUI to an existing app-server instance as its backend. When connected this way, file-change approval requests flow through the app-server → into the plugin's registered handlers → `diff.open()` is called → the Neovim diff UI appears.

No new dependencies. No architecture rewrite. Three focused changes.

## Changes

### 1. `lua/codex/terminal.lua` — cmd_override parameter

Add an optional `cmd_override` string parameter to `open`, `simple_toggle`, and `focus_toggle`. When provided it replaces `get_cmd()`.

```lua
function M.open(cmd_override)
  active_provider.open(cmd_override or get_cmd(), get_opts())
end
-- same pattern for simple_toggle, focus_toggle
```

### 2. `lua/codex/init.lua` — build_codex_cmd + :Codex command

Add a module-local helper:

```lua
local function build_codex_cmd(flag)
  local base = (M.state.config and M.state.config.codex_cmd) or "codex"
  local url  = require("codex.app_server").url()
  if not url then return nil end          -- app-server not ready
  local remote = " --remote " .. url
  if flag == "--resume" or flag == "--continue" then
    return base .. remote .. " resume --last"
  end
  return base .. remote
end
```

Modify `:Codex` command:

```
if terminal already running:
    simple_toggle()                        -- show/hide existing window
else:
    app_server.ensure(function(_, err)
        if err:
            vim.notify("codex: app-server not ready — " .. err, ERROR)
            return                         -- do NOT open terminal
        vim.schedule(→ terminal.open(build_codex_cmd(arg)))
    end)
```

### 3. `lua/codex/init.lua` — flush_mentions terminal open

When `CodexAdd`/`CodexSend` triggers a terminal open (terminal was not running):

```
url = app_server.url()
if url:
    terminal.open("codex --remote " .. url)
    vim.defer_fn(send_all, 1500)
else:
    vim.notify("codex: app-server not ready", WARN)
    -- do NOT open terminal
```

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| app-server not ready when `:Codex` is called | `vim.notify` ERROR, terminal does not open |
| app-server not ready when `CodexAdd`/`CodexSend` is called | `vim.notify` WARN, mention is dropped |
| app-server ready, `--remote` flag exists | TUI connects to app-server, diff flow works |
| `--resume`/`--continue` | `codex --remote <url> resume --last` |

## What Does NOT Change

- PTY-based `send_text` for `@mention` injection (still works the same once terminal is open)
- `diff.lua`, `handlers/`, `rpc.lua`, `transport/` — untouched
- `approval.lua` handler logic — untouched
- All other commands (`CodexFocus`, `CodexOpen`, `CodexClose`, etc.)

## Files Changed

| File | Change |
|------|--------|
| `lua/codex/terminal.lua` | Add `cmd_override` param to `open`, `simple_toggle`, `focus_toggle` |
| `lua/codex/init.lua` | Add `build_codex_cmd()`, modify `:Codex` command, modify `flush_mentions` |

## Test Plan

- `:Codex` before app-server ready → error notification, no terminal
- `:Codex` after app-server ready → terminal opens with `codex --remote ws://...`
- `:Codex` on already-running terminal → show/hide (no new process)
- `:Codex --resume` → `codex --remote ws://... resume --last`
- `CodexAdd` before app-server ready → warn notification, no open
- `CodexAdd` after app-server ready + terminal closed → opens with `--remote`, sends `@mention` after 1500ms
- `CodexAdd` after app-server ready + terminal open → sends `@mention` immediately
- codex makes a file change → `applyPatchApproval` arrives → diff UI opens in Neovim
