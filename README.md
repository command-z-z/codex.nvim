# codex.nvim

Neovim integration for [OpenAI Codex CLI](https://github.com/openai/codex).
Mirrors the [claudecode.nvim](https://github.com/coder/claudecode.nvim) interface so
switching between AI assistants feels seamless.

## Prerequisites

- Neovim ≥ 0.9
- `codex` CLI installed and in `$PATH` (`npm install -g @openai/codex` or equivalent)
- A Codex CLI version that supports `codex app-server` and TUI `--remote`

## Installation

```lua
-- lazy.nvim
{
  "command-z-z/codex.nvim",
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
map("n", "<leader>aa", "<cmd>Codex<cr>",            { desc = "Toggle Codex" })
map("n", "<leader>ar", "<cmd>Codex --resume<cr>",   { desc = "Resume Codex" })
map("n", "<leader>af", "<cmd>CodexFocus<cr>",       { desc = "Focus Codex" })
map("n", "<leader>ab", "<cmd>CodexAdd<cr>",         { desc = "Add current buffer to Codex" })
map("v", "<leader>as", ":'<,'>CodexSend<cr>",       { desc = "Send selection to Codex" })
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

  -- Diff viewer (TODO: limited by the current upstream Codex app-server API)
  diff_opts = {
    layout              = "vertical",   -- "vertical"|"horizontal"|"diffsplit"
    open_in_new_tab     = false,
    keep_terminal_focus = false,
    on_new_file_reject  = "keep_empty",
    hunk_level_review   = true,
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
    sandbox  = "read-only",           -- "read-only"|"workspace-write"|"danger-full-access"
    -- read-only (default): Codex must ask before writes.
    -- workspace-write: codex's "Auto preset" allows in-workspace writes.
    -- danger-full-access: no sandbox at all; do not use unless you know why.
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
| `:Codex` | Toggle Codex terminal panel connected to the plugin app-server |
| `:Codex --resume` | Resume last session |
| `:Codex --continue` | Continue last session |
| `:CodexFocus` | Smart focus/unfocus panel |
| `:CodexOpen` | Open panel |
| `:CodexClose` | Close panel |
| `:CodexAdd` | Add current buffer to Codex context |
| `:CodexSend` | Send visual selection to Codex (use `:'<,'>CodexSend` in visual mode) |
| `:CodexDiffAccept` | TODO: accept pending CodexDiff once the upstream app-server API exposes stable file-change approval data |
| `:CodexDiffDeny` | TODO: deny pending CodexDiff once the upstream app-server API exposes stable file-change approval data |
| `:CodexDiffAcceptAll` | TODO: batch accept pending CodexDiff once upstream support is stable |
| `:CodexDiffDenyAll` | TODO: batch deny pending CodexDiff once upstream support is stable |
| `:CodexSelectModel` | Pick from configured models |
| `:CodexStart` | Start app-server manually |
| `:CodexStop` | Stop app-server |
| `:CodexStatus` | Show connection status |

## Migration from old codex.nvim

| Old command | New command |
|-------------|-------------|
| `:CodexCLI` / `:CodexCLIToggle` | `:Codex` |
| `:CodexToggle` | `:Codex` |
| `:CodexResume` | `:Codex --resume` |
| `:CodexDiff` / `:CodexDiffToggle` | TODO: CodexDiff is blocked on stable upstream app-server diff approval support |
| `:CodexApply` | TODO: use CodexDiff approval commands after upstream support stabilizes |

## License

MIT
