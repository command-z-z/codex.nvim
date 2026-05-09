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

1. `app_server.ensure()` starts `codex app-server --listen ws://...` if needed
2. The terminal split opens `codex --remote ws://...`
3. Codex CLI TUI runs as a remote client of the same app-server connection
4. User types in the TUI; file-change and command approvals are sent back over app-server RPC

### File mention (`:CodexAdd`)

1. `init.enqueue_mention(current_buf_path)` queues the file path
2. 50ms debounce → `flush_mentions()`
3. If terminal is open: `terminal.send_text("@<path> ")` injects via PTY channel
4. If terminal is closed: start/connect app-server, open `codex --remote ws://...`, then send after 1500ms startup delay
5. Both `native` and `snacks` providers support PTY channel injection via `nvim_chan_send`

### File-range mention (`:CodexSend` on visual selection)

1. `visual_commands.handle_send(line1, line2)` builds `path:start-end`
2. `init.enqueue_mention("path:start-end")` queues the mention
3. Same flush path as `:CodexAdd` above

### Diff approval flow

```
codex app-server
  ──── request: applyPatchApproval / item/fileChange/requestApproval ────▶ handlers.init.handle_request()
                                              │
                                       handlers.diff_apply.on_request()
                                    (renders fileChanges or cached patchUpdated diff)
                                              │
                                       diff.open(patch, respond_fn, opts)
                                              │
                               [User sees split diff buffer]
                                              │
                             `:CodexDiffAccept` or `:CodexDiffDeny`
                                              │
                               diff.accept_all() / diff.deny_all()
                                              │
                               respond_fn({decision})
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
- **Remote TUI over app-server** — `app_server.lua` manages the `codex app-server` process and RPC traffic, while terminal providers launch `codex --remote <url>` so the visible TUI and Neovim approval handlers share the same backend
- **PTY-based mention injection** — `@mention` text is sent directly to the codex CLI's PTY via `nvim_chan_send(jobid, text)`. Both `native` and `snacks` providers implement `send_text` using `b:terminal_job_id`
- **Handlers dispatcher** — `handlers/init.lua` provides a registry so new RPC methods can be added without touching `init.lua`
- **Diff review markers** — `diff.lua` provides `[ACCEPT]`/`[REJECT]` hunk markers for review context; the current app-server approval response still accepts or denies the whole pending patch
- **50ms selection debounce** — prevents flooding the app-server with cursor-move events
- **Exponential-backoff auto-restart** — `app_server.lua` reschedules itself on unexpected exit (2s → 4s → 8s → 16s → 30s, max 5 attempts), counter resets on successful connection
