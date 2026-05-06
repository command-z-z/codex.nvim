# codex.nvim Mirror-claudecode Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite codex.nvim so its commands, UI behavior, configuration shape, and interaction rhythm are indistinguishable from claudecode.nvim while still driving Codex CLI under the hood (via `codex app-server` WebSocket JSON-RPC).

**Architecture:** Pure-Lua rewrite mirroring claudecode.nvim's module boundaries (`transport/`, `handlers/`, `terminal/`, `diff.lua`, `selection.lua`). Single backend = `codex app-server`. Drop `plenary` and `nui` dependencies. Reuse claudecode.nvim's MIT-licensed `server/utils.lua` (SHA-1 + Base64) and `server/frame.lua` (RFC 6455) verbatim where shape allows.

**Tech Stack:** Neovim ≥ 0.10, Lua 5.1, `vim.loop` for async I/O, `vim.system` for subprocess, busted for tests, custom vim API mock (no plenary).

**Plan scope:** Phase 0 (preparation + protocol spike) is fully detailed below. Phases 1–6 are outlined with file lists and acceptance criteria; **each later phase will get its own plan file written when started**, because Phase 4-5 details depend on what the Phase 0 spike uncovers about the codex app-server protocol.

**Reference design doc:** `~/.claude/plans/claudecode-nvim-codex-nvim-dazzling-muffin.md` (mirrored to Notion: "Vibe Coding Best Practice / codex.nvim 重构计划：与 claudecode.nvim 行为一致").

---

## Pre-Flight Checks

Before starting Task 1, verify:

- [ ] **Working directory is `/home/eugene/Desktop/MyRepo/codex.nvim`**

Run: `pwd`
Expected: `/home/eugene/Desktop/MyRepo/codex.nvim`

- [ ] **claudecode.nvim sibling exists for reference**

Run: `ls /home/eugene/Desktop/MyRepo/claudecode.nvim/lua/claudecode/server/utils.lua`
Expected: file exists.

- [ ] **codex CLI is installed**

Run: `command -v codex && codex --version`
Expected: a path and a version. If missing, `npm i -g @openai/codex` (or upstream's equivalent) before continuing.

- [ ] **Decide on isolation**: this plan does NOT mandate a worktree. If you want one, run:

```bash
git worktree add ../codex.nvim-rewrite -b refactor/mirror-claudecode
cd ../codex.nvim-rewrite
```

Otherwise work on a feature branch in-place:

```bash
git checkout -b refactor/mirror-claudecode
```

---

## Phase 0 — Preparation & Protocol Spike (target: 0.5 day)

### Task 1: Stash or commit work-in-progress

`git status` shows uncommitted changes (`config.lua` modified) and untracked files (`app_server.lua`, `rpc.lua`, `websocket.lua`). These cannot be lost — Phase 1 will reuse them as starting points.

**Files:**
- Affects: working tree only

- [ ] **Step 1: Inspect WIP**

Run: `git status --short && git diff --stat`
Expected: shows the four files listed above. If any of them is unfamiliar, ask the user before proceeding.

- [ ] **Step 2: Stash WIP under a named entry**

Run:
```bash
git stash push -u -m "wip-before-rewrite: app_server/rpc/websocket prototypes" -- \
  lua/codex/config.lua lua/codex/app_server.lua lua/codex/rpc.lua lua/codex/websocket.lua
```
Expected: `Saved working directory and index state On <branch>: wip-before-rewrite: ...`

- [ ] **Step 3: Verify clean tree**

Run: `git status`
Expected: `nothing to commit, working tree clean`. Note the stash hash for Phase 1 reference: `git stash list`.

### Task 2: Tag current state

A retreat point — if the rewrite goes sideways we can `git checkout pre-rewrite` to recover.

- [ ] **Step 1: Create the tag**

Run: `git tag -a pre-rewrite -m "Final state of plenary+nui-based codex.nvim before mirror-claudecode rewrite"`

- [ ] **Step 2: Verify**

Run: `git tag -l pre-rewrite && git show pre-rewrite --stat | head -5`
Expected: tag exists, shows the commit it points to.

### Task 3: Create design doc directory

The design doc captures *what* we are building (the spec). The implementation plan you are reading captures *how*. They are different documents.

**Files:**
- Create: `docs/specs/refactor-design.md`

- [ ] **Step 1: Make the directory**

Run: `mkdir -p docs/specs && ls -la docs/`
Expected: lists `specs/` and `superpowers/`.

- [ ] **Step 2: Write `docs/specs/refactor-design.md`**

Copy the content from `~/.claude/plans/claudecode-nvim-codex-nvim-dazzling-muffin.md` into `docs/specs/refactor-design.md`, then trim everything below the "## 当前状态" section (those entries become stale once the work begins).

Expected: file is between 200–400 lines and contains the seven locked decisions, target directory tree, command parity table, configuration shape, and risk matrix.

- [ ] **Step 3: Commit design doc**

Run:
```bash
git add docs/specs/refactor-design.md
git commit -m "docs: add refactor design doc mirroring claudecode.nvim"
```

### Task 4: Protocol spike — discover codex app-server surface

This is the highest-risk unknown. Phase 4 (blocking diff) and Phase 5 (approvals) need to know exactly what notifications and methods `codex app-server` exposes. Spend up to **half a working day** on this and write findings to `PROTOCOL.md`.

**Files:**
- Create: `PROTOCOL.md`
- Reference: existing `lua/codex/app_server.lua` (stashed) — already has approval-denial logic that names protocol methods

- [ ] **Step 1: Pull stash to see what we already know**

Run: `git stash show -p stash@{0} -- lua/codex/app_server.lua | head -120`
Expected: source for app_server with method names like `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/tool/requestUserInput`. Record these names.

- [ ] **Step 2: Start `codex app-server` manually and observe handshake**

Run in one terminal:
```bash
codex app-server --listen ws://127.0.0.1:45123 2>&1 | tee /tmp/codex-spike.log
```

In another, hand-shake with a minimal websocat or netcat session and send `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`. Record what comes back.

(If `websocat` is unavailable, install via `cargo install websocat` or use Python's `websockets` library:
```bash
python3 -c "
import asyncio, websockets, json
async def main():
    async with websockets.connect('ws://127.0.0.1:45123') as ws:
        await ws.send(json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}}))
        for _ in range(5): print(await ws.recv())
asyncio.run(main())
"
```)

Expected: capture at least the response to `initialize` and one round of `prompt`-style request. Save raw frames to `/tmp/codex-spike.log`.

- [ ] **Step 3: Inspect upstream `codex` source**

Run: `which codex` then `head -2 "$(which codex)"` — if it is a Node/JS launcher, find the install path with `npm root -g`. If it's a Rust binary, locate the source repo (likely github.com/openai/codex or similar) and `git clone` to `/tmp/codex-source` for read-only inspection.

Look for files with `app-server` or `app_server` in the name and grep for JSON-RPC method registrations.

Expected: a list of method names beyond what app_server.lua already references.

- [ ] **Step 4: Write `PROTOCOL.md`**

Create `PROTOCOL.md` with these sections:

```markdown
# codex app-server Protocol Notes

> Reverse-engineered against codex CLI version: <fill from `codex --version`>
> Last verified: 2026-05-06

## Transport

- WebSocket on ws://127.0.0.1:<port>, no TLS, no auth header.
- Frames: text only (utf-8 JSON), no binary.
- Each frame is a complete JSON-RPC 2.0 message.

## Initialize handshake

Client sends:
\```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{<observed fields>}}
\```

Server responds:
\```json
<paste actual response from /tmp/codex-spike.log>
\```

## Notifications (server → client)

| Method | Direction | Purpose | Fields |
|--------|-----------|---------|--------|
| <method>  | server→client | <description> | <observed JSON shape> |

## Requests (server → client, expect response)

| Method | Direction | Purpose | Response shape |
|--------|-----------|---------|----------------|
| `item/commandExecution/requestApproval` | server→client | Codex wants to run a shell command | `{ "approved": bool }` |
| `item/fileChange/requestApproval` | server→client | Codex wants to write a file | `{ "approved": bool }` |
| `item/tool/requestUserInput` | server→client | Codex wants user input mid-task | `{ "input": string }` |

## Methods (client → server)

| Method | Purpose | Params |
|--------|---------|--------|
| `initialize` | Bootstrap | <observed> |
| <method>     | <purpose>  | <observed> |

## Open questions

- <list anything you couldn't determine — these become Phase 4/5 spike sub-tasks>
```

Fill in the `<...>` placeholders with the actual observations from Steps 2–3. Do not leave any `<...>` in the committed file.

- [ ] **Step 5: Commit protocol notes**

Run:
```bash
git add PROTOCOL.md
git commit -m "docs: capture codex app-server protocol from spike"
```

### Task 5: Clear `lua/codex/`

The rewrite is going to be incompatible with the current source. Wipe it now so accidental imports from the old code can't happen. The old code is preserved by tag `pre-rewrite` and stash entries.

**Files:**
- Delete: every file under `lua/codex/`
- Keep: `plugin/codex.lua` (rewrite still uses this loader hook)

- [ ] **Step 1: Verify the tag and stash exist before deleting**

Run: `git tag -l pre-rewrite && git stash list | head -3`
Expected: tag is listed; stash includes `wip-before-rewrite`. **If either is missing, STOP** — do not delete.

- [ ] **Step 2: Remove old source**

Run: `git rm -r lua/codex/`
Expected: every file under `lua/codex/` is staged for deletion.

- [ ] **Step 3: Verify `plugin/codex.lua` is untouched**

Run: `cat plugin/codex.lua`
Expected: still present and contains the original loader (a 3-line guard).

- [ ] **Step 4: Stub a new `lua/codex/init.lua`**

Create `lua/codex/init.lua` so `require('codex')` does not blow up while later phases land. Write exactly:

```lua
local M = {}

function M.setup(opts)
  vim.notify(
    "[codex.nvim] rewrite in progress — full functionality returning in Phase 2",
    vim.log.levels.WARN
  )
  M.opts = opts or {}
end

return M
```

- [ ] **Step 5: Commit the wipe**

Run:
```bash
git add lua/codex/init.lua
git commit -m "refactor: wipe lua/codex/ for mirror-claudecode rewrite

Old source preserved at tag pre-rewrite. Resumes via Phase 1+ in
docs/superpowers/plans/2026-05-06-codex-nvim-mirror-claudecode.md."
```

### Task 6: README migration banner

Existing users running `:CodexCLI`, `:CodexResume`, `:CodexDiff`, etc. would otherwise hit silent breakage between Phase 0 and Phase 2. A banner at the top of README warns them.

**Files:**
- Modify: `README.md` (insert banner immediately after the title)

- [ ] **Step 1: Read current README header**

Run: `head -20 README.md`
Expected: shows the project title and probably installation instructions.

- [ ] **Step 2: Insert migration banner**

Edit `README.md` so that immediately after the H1 title there is this block (preserve any existing content below):

```markdown
> ⚠️ **Migration in progress (2026-05-06):** codex.nvim is being rewritten to mirror
> [claudecode.nvim](https://github.com/coder/claudecode.nvim) so Claude/Codex switching feels seamless.
> During Phase 0–2 (~3 days), most commands are temporarily unavailable. Pin to tag
> `pre-rewrite` if you need the old plenary+nui-based plugin:
>
> ```lua
> { "command-z-z/codex.nvim", tag = "pre-rewrite" }
> ```
>
> Track progress: `docs/superpowers/plans/2026-05-06-codex-nvim-mirror-claudecode.md`.
```

- [ ] **Step 3: Commit banner**

Run:
```bash
git add README.md
git commit -m "docs(readme): add migration banner pointing at pre-rewrite tag"
```

### Task 7: Create test scaffolding

Phase 1 starts with TDD — but there is no test runner yet. Set up a minimal busted entry point that does NOT depend on plenary.

**Files:**
- Create: `tests/minimal_init.lua`
- Create: `tests/mocks/vim.lua` (will be filled in Phase 1; stub for now)
- Create: `tests/unit/.gitkeep`
- Create: `tests/integration/.gitkeep`
- Modify: `Makefile` or create one if absent

- [ ] **Step 1: Create the directory tree**

Run: `mkdir -p tests/unit tests/integration tests/mocks && touch tests/unit/.gitkeep tests/integration/.gitkeep`

- [ ] **Step 2: Write `tests/minimal_init.lua`**

```lua
-- Minimal test harness for codex.nvim. No plenary dependency.
local repo_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(repo_root)
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
package.path = repo_root .. "/tests/?.lua;" .. repo_root .. "/tests/?/init.lua;" .. package.path
```

- [ ] **Step 3: Stub the vim mock**

Write `tests/mocks/vim.lua` with this placeholder so `require('mocks.vim')` does not crash. The full mock comes in Phase 1.

```lua
-- Placeholder. Phase 1 fills this in by porting claudecode.nvim/tests/mocks/vim.lua.
error("tests/mocks/vim.lua: not yet implemented — see Phase 1 Task 1")
```

- [ ] **Step 4: Add a Makefile target**

Create or extend `Makefile`:

```makefile
.PHONY: test test-unit test-integration

test: test-unit test-integration

test-unit:
	@busted --helper=tests/minimal_init.lua --pattern=_spec tests/unit

test-integration:
	@busted --helper=tests/minimal_init.lua --pattern=_spec tests/integration
```

- [ ] **Step 5: Verify busted is available**

Run: `command -v busted || luarocks install busted`
Expected: a path. If `luarocks` is also missing, `sudo pacman -S luarocks` (Arch) or `brew install luarocks` (mac).

- [ ] **Step 6: Run the empty suite to confirm wiring**

Run: `make test-unit 2>&1 | head -10`
Expected: `0 successes / 0 failures` or "no test files found" — either is fine. We just want busted to exit 0.

- [ ] **Step 7: Commit scaffolding**

Run:
```bash
git add tests/ Makefile
git commit -m "test: scaffold busted runner without plenary dependency"
```

### Task 8: Phase 0 closeout

- [ ] **Step 1: Tag end of Phase 0**

Run: `git tag -a phase-0-complete -m "Prep + protocol spike done"`

- [ ] **Step 2: Sanity-check the new state**

Run:
```bash
git log --oneline pre-rewrite..HEAD
ls lua/codex/
ls docs/
```

Expected:
- 5 new commits (design doc, protocol notes, wipe, banner, test scaffolding)
- `lua/codex/` contains only `init.lua`
- `docs/` contains `specs/` and `superpowers/`

- [ ] **Step 3: Push branch (optional)**

If working with a remote: `git push -u origin refactor/mirror-claudecode`. If local-only, skip.

---

## Phase 1 — Transport Layer (target: 3–4 days)

> A separate plan file `docs/superpowers/plans/<date>-phase-1-transport.md` will be written immediately before starting Phase 1, using fresh writing-plans against the spike output captured in `PROTOCOL.md`. The outline below sets boundaries.

**Goal:** Pure-Lua WebSocket *client* (not server — Codex is server) that opens a persistent connection to `codex app-server`, exchanges JSON-RPC 2.0 messages, and survives reconnects.

**Files to create:**
- `lua/codex/transport/utils.lua` — port from `claudecode.nvim/lua/claudecode/server/utils.lua` (SHA-1 + Base64); strip server-side `accept_key` since we are the client
- `lua/codex/transport/frame.lua` — port from `claudecode.nvim/lua/claudecode/server/frame.lua` (RFC 6455 codec, both directions used)
- `lua/codex/transport/handshake.lua` — **new**: client-side upgrade. Generate random `Sec-WebSocket-Key`, send GET request, validate server's `Sec-WebSocket-Accept` (SHA-1(key + magic)). Different from claudecode.nvim's `handshake.lua` which only handles server side.
- `lua/codex/transport/tcp.lua` — `vim.loop.new_tcp() :: connect()`. Single-connection client, not a listener. Differs from claudecode.nvim's `tcp.lua` in role.
- `lua/codex/transport/session.lua` — state machine: `idle → connecting → handshaking → open → closing → closed`. 30 s ping/pong heartbeat.
- `lua/codex/transport/init.lua` — facade module exposed as `codex.transport`.
- `lua/codex/rpc.lua` — JSON-RPC 2.0 wrapper. Reuse logic from the stashed prototype (`git stash show -p stash@{0} -- lua/codex/rpc.lua`) but wire it on top of `transport/` instead of the old monolithic `websocket.lua`.
- `lua/codex/app_server.lua` — supervises `codex app-server --listen ws://127.0.0.1:<port>`. Use `vim.system` (Neovim 0.10+) instead of `plenary.job`. Port range scan, exit cleanup on `VimLeavePre`.

**Acceptance criteria:**
1. `tests/unit/transport_frame_spec.lua` round-trips text frames of length 0, 125, 126, 65535, 65536+ bytes (covers 7-bit / 16-bit / 64-bit length fields).
2. `tests/unit/transport_utils_spec.lua` confirms SHA-1 against a known vector and Base64 round-trips bytes 0x00–0xFF.
3. `tests/integration/handshake_spec.lua` opens a real `codex app-server` on a random port, completes the WS handshake, and sends `initialize`. Asserts the response matches the schema captured in `PROTOCOL.md`.
4. `tests/integration/session_spec.lua` keeps the connection alive for 90 s with no traffic, then sends a request and gets a response (proves ping/pong is doing its job).
5. `make test` exits 0.

**Tasks expected (~10 atomic):**
1. Restore stashed prototypes onto a scratch branch for reference: `git checkout stash@{0} -- lua/codex/rpc.lua lua/codex/websocket.lua lua/codex/app_server.lua && git restore --staged lua/codex/` (read-only — do not commit).
2. Port `tests/mocks/vim.lua` from `claudecode.nvim/tests/mocks/vim.lua`.
3. Implement `transport/utils.lua` (TDD against SHA-1 vectors + base64 round-trip).
4. Implement `transport/frame.lua` (TDD against length boundaries + masking).
5. Implement `transport/handshake.lua` (TDD against a fake server response).
6. Implement `transport/tcp.lua` (integration test against `nc -l`).
7. Implement `transport/session.lua` (state-machine test + heartbeat test).
8. Implement `rpc.lua` (TDD against pending-request map + timeout behavior).
9. Implement `app_server.lua` supervisor (integration test that spawns and kills `codex app-server`).
10. Wire `transport/init.lua` facade and add a smoke integration test that goes end-to-end (spawn → handshake → ping/pong → initialize → close).

---

## Phase 2 — Core Panel & Commands (target: 2–3 days)

**Goal:** Implement every command from the parity table (`:Codex`, `:Codex --resume`, `:Codex --continue`, `:CodexFocus`, `:CodexOpen`, `:CodexClose`, `:CodexAdd`, `:CodexSend`, `:CodexDiffAccept`, `:CodexDiffDeny`, `:CodexSelectModel`, `:CodexStart`, `:CodexStop`, `:CodexStatus`) with a working terminal panel.

**Files to create:**
- `lua/codex/init.lua` — replace the Phase 0 stub. Owns `setup(opts)`, command registrations, the `@mention` queue stub (queue object exists, draining wired up later in Phase 5), shutdown handlers.
- `lua/codex/config.lua` — defaults + validation. Detect old keys (`backend`, `cli`, `chat.sandbox`, etc.) and emit `vim.notify(..., WARN)` mapping each to its new home.
- `lua/codex/terminal.lua` — provider interface (`open / close / simple_toggle / focus_toggle / get_active_bufnr / is_available`). Mirror `claudecode.nvim/lua/claudecode/terminal.lua:1-200`.
- `lua/codex/terminal/native.lua` — `vim.api.nvim_open_term` fallback.
- `lua/codex/terminal/snacks.lua` — `snacks.nvim` adapter; gracefully `is_available() == false` if snacks is not installed.
- `lua/codex/terminal/external.lua` — launch in alacritty/iTerm/etc. Pulls config from `terminal.provider_opts.external_terminal_cmd`.
- Wrapper commands for the seven removed legacy commands (`:CodexCLI`, `:CodexResume`, `:CodexDiff`, …) that print `vim.notify` migration hints. Live in `lua/codex/init.lua`.

**Acceptance criteria:**
1. `:Codex` toggles a terminal split running `codex app-server` on the right (default 30 % width).
2. `:Codex --resume` and `:Codex --continue` both succeed and pass the flag through to the spawned process (verified via `ps -ef | grep codex`).
3. `:CodexStop` cleanly kills the subprocess and closes the WS session.
4. Running any of the removed commands prints the migration hint and returns without erroring.
5. `make test` exits 0; new specs cover command argument parsing and terminal provider selection.

---

## Phase 3 — Context & Selection (target: 2 days)

**Goal:** Real-time selection tracking, context builders, visual-range commands.

**Files:**
- `lua/codex/selection.lua` — port from `claudecode.nvim/lua/claudecode/selection.lua`. 50 ms debounce, push `selection_changed` notification through `rpc.lua`.
- `lua/codex/context.lua` — buffer / range / diagnostics / git-diff context builders. Reuse logic from the stashed `lua/codex/context.lua`; strip plenary.
- `lua/codex/visual_commands.lua` — capture visual range before mode change, mirror `claudecode.nvim/lua/claudecode/visual_commands.lua`.

**Acceptance criteria:**
1. Holding visual selection for 200 ms triggers exactly one `selection_changed` notification (debounce works).
2. `:'<,'>CodexSend` sends the highlighted range as a structured payload visible in `codex app-server` debug log.
3. `:CodexAdd <file> <start> <end>` accepts 1-indexed lines and rejects 0 or out-of-range values with a helpful error.

---

## Phase 4 — Blocking Diff (target: 3–4 days)

> **High risk.** Implementation depends heavily on Phase 0 spike output. Do not start until `PROTOCOL.md` has documented the exact shape of `item/fileChange/requestApproval` (or whatever the equivalent notification is called in the version we target).

**Goal:** When codex wants to write a file, surface a side-by-side diff in Neovim, block the RPC response until the user runs `:CodexDiffAccept` or `:CodexDiffDeny`, then return the result so codex either persists the change or aborts.

**Files:**
- `lua/codex/diff.lua` — port the unified-diff parser and hunk tree from the stashed `lua/codex/diff.lua` (it already works). Replace the old NUI popup UI with native splits modeled on `claudecode.nvim/lua/claudecode/diff.lua`. Keep the hunk-level review keymaps (`a` / `r` / `A` / `R` / `p` / `x`) — that's a codex.nvim feature worth preserving.
- `lua/codex/handlers/diff_apply.lua` — receives the file-change request, opens the diff, blocks until the user resolves, returns `{ approved = bool }`.
- `lua/codex/handlers/init.lua` — dispatcher table: method name → handler.

**Acceptance criteria:**
1. End-to-end test: prompt codex to "rename the variable `foo` to `bar` in `tests/fixtures/sample.lua`". Diff appears in a vertical split. `:CodexDiffAccept` writes the change; the codex process logs receipt of the approval. `:CodexDiffDeny` leaves the file untouched.
2. Multi-file patches: codex requests changes to two files in sequence — both diffs queue up, second is offered after first resolves.
3. Hunk-level review keymaps still work inside the new UI.

---

## Phase 5 — Approvals & @mention Queue (target: 2 days)

**Goal:** Surface codex's other approval requests (command execution, user input) as user-visible prompts. Implement the @mention queue with debounce + offline buffering.

**Files:**
- `lua/codex/handlers/approval.lua` — three policies: `prompt` (default — `vim.fn.input` / floating Y/N), `auto-deny` (preserves current codex.nvim behavior), `auto-allow`.
- `lua/codex/handlers/progress.lua` — render progress notifications in the panel; toggle compact/verbose with a keymap.
- Extend `lua/codex/init.lua` mention queue: connected → 50 ms debounce batch send; disconnected → enqueue, drain on connect (10 s connection timeout, 5 s per-item expiry, 25 ms inter-item delay).

**Acceptance criteria:**
1. `approval.policy = "prompt"` blocks until the user types `y` or `n`, returns the matching response.
2. `approval.policy = "auto-deny"` returns `{approved = false}` instantly; `auto-allow` returns `{approved = true}` instantly.
3. `:CodexSend` while disconnected enqueues the mention; reconnecting drains the queue in order with the configured delays.

---

## Phase 6 — Polish & Documentation (target: 2 days)

**Goal:** Production-readiness: structured logging, crash recovery, complete docs.

**Files:**
- `lua/codex/logger.lua` — trace/debug/info/warn/error with file output controlled by `log_level`.
- Crash recovery: when `app_server.lua` detects the subprocess exited, schedule a restart with exponential backoff (1 s, 2 s, 5 s, 10 s, give up).
- `ARCHITECTURE.md` — module diagram + data flow.
- `README.md` — full rewrite. Sections: install, quick start, configuration, command reference, migration from pre-rewrite, troubleshooting.
- Test coverage report; goal ≥ 80 %.

**Acceptance criteria:**
1. Killing `codex app-server` externally during a session shows a `vim.notify` warning and reconnects within 10 s without user action.
2. Following only the new README quick-start lands a working `:Codex` panel on a clean Neovim install.
3. `make test` reports ≥ 80 % line coverage on `lua/codex/`.

---

## Self-Review Notes

**Spec coverage:** all seven locked decisions from the design doc map to one or more tasks above (route → entire plan; scope → Phase 2 command list excludes file-tree; backend → Phase 1 transport only talks to app_server; deps → no plenary/nui import anywhere; rewrite → Phase 0 wipe; commands → Phase 2 + migration wrappers; approval → Phase 5 policy switch).

**Placeholder check:** Phase 0 (Tasks 1–8) contains no TBD/TODO/etc. and every step shows the actual command, code, or file content. Phases 1–6 are explicitly marked as outlined-only with their own follow-up plan files; that is a stated scope decision, not a placeholder.

**Type/name consistency:** `transport/` is the directory; `lua/codex/transport/init.lua` is the facade module. `handlers/` houses upstream-event handlers. Command names match the spec table exactly. The legacy command list is the same in Phase 0 Task 6 (banner) and Phase 2 (wrappers).

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-06-codex-nvim-mirror-claudecode.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review, fastest iteration with the most context isolation.

2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batched with checkpoints between tasks.

Per the user's plan ("execute Option A"), Phase 0 begins immediately after this plan is committed.
