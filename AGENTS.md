# Repository Guidelines

## Project Structure & Module Organization

This repository is a Neovim Lua plugin with zero runtime dependencies (no plenary, no nui).
Runtime entrypoint: `plugin/codex.lua`. Implementation modules live under `lua/codex/`:

| Module | Role |
|--------|------|
| `init.lua` | Command registration, mention queue, connection orchestration |
| `config.lua` | Defaults and validation |
| `app_server.lua` | Codex process lifecycle, WebSocket client, JSON-RPC 2.0 |
| `rpc.lua` | JSON-RPC request/notify/respond primitives |
| `transport/` | Pure-Lua WebSocket (TCP + framing + handshake) |
| `terminal.lua` | Provider abstraction (`native` / `snacks` / `external` / `none`) |
| `terminal/native.lua` | Neovim built-in terminal provider |
| `terminal/snacks.lua` | snacks.nvim terminal provider |
| `selection.lua` | Cursor/visual-selection tracking (50ms debounce) |
| `visual_commands.lua` | Range command helpers for `CodexSend` |
| `diff.lua` | Unified-diff viewer with per-hunk accept/reject |
| `handlers/init.lua` | RPC method dispatcher |
| `handlers/diff_apply.lua` | `applyPatchApproval` handler |
| `handlers/approval.lua` | Shell-command approval handler |

Tests live in `tests/` and use `tests/minimal_init.lua` as the headless init file.

## Build, Test, and Development Commands

There is no build step; Neovim loads the Lua files directly.

Run the full test suite with:

```sh
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedDirectory tests { minimal_init = "tests/minimal_init.lua" }'
```

For local manual testing, install this checkout through your plugin manager with
`dir = "/path/to/codex.nvim"` and call `require("codex").setup()`.
The plugin requires Neovim ≥ 0.9 and the `codex` CLI in `$PATH`.

## Coding Style & Naming Conventions

- Lua module tables: `local M = {}` … `return M`
- Four-space indentation, snake_case throughout
- Command registration in `init.lua`, defaults in `config.lua`
- No new runtime dependencies — use Neovim APIs and libuv only

## Testing Guidelines

Tests use Plenary's busted-style framework. Add or update `*_spec.lua` files in `tests/`
near the behavior being changed. Keep tests deterministic; mock jobs, buffers, and
terminal state rather than requiring a live codex session. Run the full headless suite
before submitting changes.

## Commit & Pull Request Guidelines

Use concise imperative subjects: `feat:`, `fix:`, `refactor:`, `docs:`, `test:` prefixes.
Keep titles short and focused on the user-visible or architectural change.

Pull requests should include a brief description and the commands run for verification.
Call out any configuration key additions or removals — update `README.md` accordingly.

## Agent-Specific Instructions

- Do not rewrite unrelated behavior while fixing a narrow issue.
- Preserve existing configuration keys; add new ones with sensible defaults.
- Update `README.md` when commands, defaults, or user-facing keymaps change.
- Update `ARCHITECTURE.md` when data-flow or module relationships change.
