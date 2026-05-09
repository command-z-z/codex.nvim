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
- **Exponential-backoff auto-restart** — `app_server.lua` reschedules itself on unexpected exit (2s → 4s → 8s → 16s → 30s, max 5 attempts), counter resets on successful connection
