# codex app-server Protocol Notes

> Reverse-engineered against codex CLI version: 0.128.0
> Last verified: 2026-05-06
> Platform: Linux x86-64 (Arch Linux)

## Transport

- WebSocket on `ws://127.0.0.1:<port>` — no TLS, no auth header required.
- Frames: text only (UTF-8 JSON). No binary frames observed.
- Each frame is a **complete** JSON-RPC 2.0 message (not streamed across frames).
- Server binds localhost only. Remote access requires SSH port-forwarding.
- Additional HTTP endpoints on the same port:
  - `GET /readyz` — readiness probe
  - `GET /healthz` — liveness probe

## Server startup

```bash
codex app-server --listen ws://127.0.0.1:<port>
```

Stdout on startup:
```
codex app-server (WebSockets)
  listening on: ws://127.0.0.1:<port>
  readyz: http://127.0.0.1:<port>/readyz
  healthz: http://127.0.0.1:<port>/healthz
  note: binds localhost only (use SSH port-forwarding for remote access)
```

## Initialize handshake

### Step 1 — WS upgrade (client → server)

Standard RFC 6455 HTTP upgrade. No special headers beyond the standard WS headers.

```
GET / HTTP/1.1
Host: 127.0.0.1:<port>
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <base64-random>
Sec-WebSocket-Version: 13
```

Server responds with `101 Switching Protocols`.

### Step 2 — initialize (client → server)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "clientInfo": {
      "name": "codex.nvim",
      "title": "codex.nvim",
      "version": "0.1.0"
    },
    "capabilities": {
      "experimentalApi": true
    }
  }
}
```

**Optional params fields** (from binary type analysis):
- `writableRoots` — array of absolute paths the client may write
- `excludeTmpdirEnvVar` — bool
- `excludeSlashTmp` — bool
- `approvalPolicy` — see §Approval Policies
- `profile` — profile name string
- `optOutNotificationMethods` — array of notification method strings to suppress

### Step 3 — initialize response (server → client)

```json
{
  "id": 1,
  "result": {
    "userAgent": "codex.nvim/0.128.0 (Arch Linux Unknown; x86_64) kitty_0.46.2_ (codex.nvim; 0.1.0)",
    "codexHome": "/home/<user>/.codex",
    "platformFamily": "unix",
    "platformOs": "linux"
  }
}
```

### Step 4 — initialized notification (client → server)

After processing the `initialize` response the client **must** send this or the server will not process subsequent requests:

```json
{
  "jsonrpc": "2.0",
  "method": "initialized",
  "params": {}
}
```

## Approval Policies

Valid values for `approvalPolicy` in `thread/start` and `turn/start`:

| Value | Meaning |
|-------|---------|
| `never` | Auto-approve everything (no approval requests sent to client) |
| `on-request` | Approve commands and patches only when the model uses them |
| `on-failure` | Auto-approve first attempt; ask only when it fails |
| `granular` | Fine-grained per-tool control |
| `untrusted` | Deny-first; client must explicitly approve |

## Methods (client → server)

### `thread/start`

Start a new conversation thread. Returns the thread object.

**Params:**
```json
{
  "cwd": "/path/to/project",
  "approvalPolicy": "never",
  "sessionStartSource": "startup",
  "model": "gpt-4o",
  "sandbox": "workspace-write",
  "profile": null
}
```

**Response:**
```json
{
  "id": 2,
  "result": {
    "thread": {
      "id": "<uuid>",
      "forkedFromId": null,
      "preview": "",
      "ephemeral": false,
      "modelProvider": "openai",
      "createdAt": 1778071741,
      "updatedAt": 1778071741,
      "status": { "type": "idle" },
      "path": "/home/<user>/.codex/sessions/...",
      "cwd": "/path/to/project",
      "cliVersion": "0.128.0",
      "source": "vscode",
      "name": null,
      "turns": []
    },
    "model": "gpt-5.4-mini",
    "modelProvider": "openai",
    "serviceTier": null,
    "cwd": "/path/to/project",
    "approvalPolicy": "never",
    "approvalsReviewer": "user",
    "sandbox": { "type": "readOnly", "networkAccess": false },
    "reasoningEffort": "medium"
  }
}
```

### `turn/start`

Submit a prompt and start a turn on an existing thread.

**Params:**
```json
{
  "threadId": "<thread-uuid>",
  "cwd": "/path/to/project",
  "approvalPolicy": "on-request",
  "model": null,
  "input": [
    { "type": "text", "text": "Your prompt here" }
  ]
}
```

**Response:**
```json
{
  "id": 3,
  "result": {
    "turn": {
      "id": "<turn-uuid>",
      "items": [],
      "status": "inProgress",
      "error": null,
      "startedAt": null,
      "completedAt": null,
      "durationMs": null
    }
  }
}
```

## Notifications (server → client)

All notifications have the shape `{"method": "<name>", "params": {...}}` with no `id` or `jsonrpc` field.

### Connection lifecycle

| Method | When | Key params |
|--------|------|-----------|
| `remoteControl/status/changed` | On connect | `status` ("disabled"\|"enabled"), `environmentId` |
| `mcpServer/startupStatus/updated` | MCP server lifecycle | `name`, `status` ("starting"\|"ready"\|"error"), `error` |

### Thread lifecycle

| Method | When | Key params |
|--------|------|-----------|
| `thread/started` | Thread created | `thread` (full object) |
| `thread/status/changed` | Thread state changes | `threadId`, `status.type` ("idle"\|"active"\|"systemError") |
| `thread/name/updated` | Thread auto-named | `threadId`, `name` |
| `thread/archived` | Thread archived | `threadId` |
| `thread/unarchived` | Thread unarchived | `threadId` |
| `thread/closed` | Thread closed | `threadId` |
| `thread/compacted` | Context compacted | `threadId` |
| `thread/tokenUsage/updated` | Token count changed | `threadId`, token fields |
| `thread/goal/updated` | Goal set | `threadId`, `goal` |
| `thread/goal/cleared` | Goal cleared | `threadId` |

### Turn lifecycle

| Method | When | Key params |
|--------|------|-----------|
| `turn/started` | Turn begins processing | `threadId`, `turn` (object with `id`, `status`) |
| `turn/completed` | Turn finishes | `threadId`, `turn.status` ("completed"\|"failed"), `turn.error` |
| `turn/diff/updated` | Diff preview updated | `threadId`, `turnId` |
| `turn/plan/updated` | Plan updated | `threadId`, `turnId` |

### Item lifecycle

All item notifications include `threadId` and `turnId`.

| Method | When | Key params |
|--------|------|-----------|
| `item/started` | Item begins | `item.type`, `item.id` |
| `item/completed` | Item ends | `item` (full object) |
| `item/plan/delta` | Plan text streaming | `delta`, `text` |
| `item/agentMessage/delta` | Agent response streaming | `delta` |
| `item/reasoning/textDelta` | Reasoning streaming | `delta` |
| `item/reasoning/summaryTextDelta` | Reasoning summary streaming | `delta` |
| `item/reasoning/summaryPartAdded` | Reasoning summary part done | fields TBD |
| `item/fileChange/patchUpdated` | Patch being built | patch fields TBD |
| `item/fileChange/outputDelta` | File change output streaming | `delta` |
| `item/commandExecution/outputDelta` | Shell command output streaming | `delta` |
| `item/commandExecution/terminalInteraction` | Terminal input/output | fields TBD |
| `item/mcpToolCall/progress` | MCP tool progress | fields TBD |
| `item/autoApprovalReview/started` | Auto-approval review begins | fields TBD |
| `item/autoApprovalReview/completed` | Auto-approval review ends | fields TBD |

**Observed `item.type` values:** `userMessage`, `commandExecution`, `fileChange`, (more TBD)

### Other notifications

| Method | When | Key params |
|--------|------|-----------|
| `warning` | Non-fatal server warning | `threadId`, `message` |
| `error` | Fatal turn error | `threadId`, `turnId`, `error.message`, `error.codexErrorInfo`, `willRetry` |
| `account/rateLimits/updated` | Rate limit state changed | `rateLimits` object |
| `skills/changed` | Skills list changed | fields TBD |
| `hook/started` | Hook execution begins | fields TBD |
| `hook/completed` | Hook execution ends | fields TBD |
| `fs/changed` | Watched filesystem path changed | fields TBD |

## Requests (server → client, expect response)

These are server-initiated JSON-RPC calls with an `id`. The client **must** respond.

### `applyPatchApproval`

Server asks permission to apply a file patch.

**Server sends:**
```json
{
  "jsonrpc": "2.0",
  "id": <server-assigned-id>,
  "method": "applyPatchApproval",
  "params": {
    "callId": "<uuid>",
    "patch": "<unified diff string>",
    "reason": "<optional explanation>"
  }
}
```

**Client must respond:**
```json
{
  "jsonrpc": "2.0",
  "id": <same-id>,
  "result": { "decision": "approved" }
}
```
or
```json
{
  "jsonrpc": "2.0",
  "id": <same-id>,
  "result": { "decision": "denied" }
}
```

### `item/commandExecution/requestApproval` (alias: `ExecCommandApproval`)

Server asks permission to run a shell command.

**Server sends params:** (fields from binary type analysis)
- `callId` — identifier correlates with `ExecCommandBeginEvent`/`ExecCommandEndEvent`

**Client response result:** `{ "decision": "approved" | "denied" }`

### `item/permissions/requestApproval`

Server asks for additional filesystem/network permissions.

**Client response result:** `{ "decision": "approved" | "denied" }`

### `item/fileChange/requestApproval`

Older alias for `applyPatchApproval` (same semantics, may appear in older protocol versions).

**Client response result:** `{ "decision": "approved" | "denied" }`

### `item/tool/requestUserInput` (alias: `mcpServer/elicitation/request`)

Server needs free-form user input mid-turn (e.g. for interactive prompts).

**Client response result:** `{ "decision": "declined" }` or `{ "input": "<string>" }`

## Open Questions

- Exact `params` shape for `applyPatchApproval` — `callId` / `reason` field names need live capture with a paid account (usage limit hit during spike).
- Exact shape of `item/commandExecution/requestApproval` params — need live approval flow capture.
- Does `turn/steer` exist as a separate method, or is it a flag on `turn/start`? (binary mentions "turn/steer" in error message about active turn).
- `item.type` full enum — observed `userMessage`, `commandExecution`; need `fileChange`, `agentMessage`, `plan`, `reasoning` confirmed.
- `fs/watch` / `fs/unwatch` param shapes for Phase 3 selection tracking.
- Whether `selection_changed` notification is supported or if selection must be embedded in `turn/start` input.
- `thread/realtime/*` methods — voice/realtime API, not needed for Phase 1-5.

## Notes for Implementation

- The `jsonrpc: "2.0"` field is **absent** from server notifications in observed traffic (only `method` + `params`). Include it in client messages regardless.
- `initialized` notification has empty `params: {}` — do not omit the params field.
- `thread/start` returns a `result.thread.id` **and** a `result.model` (the active model after defaults). Use `result.thread.id` as `threadId` in subsequent calls.
- `turn/start` returns immediately with the turn ID; the actual work proceeds asynchronously via notifications.
- When `turn/completed` arrives with `status: "failed"`, check `turn.error.codexErrorInfo` for structured error codes (e.g. `"usageLimitExceeded"`).
