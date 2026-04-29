# ✨ codex.nvim

<p align="center">
  <img alt="Neovim" src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=for-the-badge&logo=neovim&logoColor=white" />
  <img alt="Codex CLI" src="https://img.shields.io/badge/Codex-CLI-111827?style=for-the-badge&logo=openai&logoColor=white" />
  <img alt="Lua" src="https://img.shields.io/badge/Lua-plugin-2C2D72?style=for-the-badge&logo=lua&logoColor=white" />
</p>

`codex.nvim` keeps the original Codex CLI experience inside Neovim and adds a
native side-panel workflow for selected-code questions, AI edits, and hunk-level
diff review.

## 🚀 Features

- 🧠 Ask Codex about the current file or visual selection
- 🛠️ Request code edits from Neovim
- 🧩 Review generated patches hunk by hunk
- ✅ Accept/reject individual hunks before applying
- 🖥️ Open the original Codex TUI without losing CLI features
- 🔁 Resume Codex sessions from a Neovim terminal split
- 🧪 Small, testable Lua modules built around `plenary.nvim`

## 📦 Requirements

- Neovim 0.10+
- `codex` CLI available in `$PATH`
- `nvim-lua/plenary.nvim`
- `MunifTanjim/nui.nvim`

Optional:

- `sindrets/diffview.nvim` for your existing Git diff workflow

## ⚡ Installation

### lazy.nvim

```lua
{
  "command-z-z/codex.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("codex").setup()
  end,
}
```

### Local Development

Use this while developing the plugin from this repository:

```lua
{
  dir = "/home/eugene/Desktop/MyRepo/codex.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("codex").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "command-z-z/codex.nvim",
  requires = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("codex").setup()
  end,
})
```

## ⌨️ Commands

| Command | Description |
| --- | --- |
| `:Codex` | Open the native Codex side panel |
| `:CodexDiff` | Open the pending hunk review UI |
| `:CodexApply` | Apply accepted hunks |
| `:CodexCLI [args...]` | Open the original Codex TUI |
| `:CodexResume [args...]` | Open `codex resume` in the current cwd |

## 💬 Chat Context

Select code in visual mode and press `<leader>aq` to attach that selection to
the Codex chat prompt. The chat history shows a compact context summary with
the file, line range, and line count; the full selected code is kept out of the
visible history and sent only with your next prompt.

Inside the chat UI, `<C-k>` focuses the output window from the prompt and
`<C-j>` returns to the prompt from the output window. Configure
`ui.keymaps.focus_output` and `ui.keymaps.focus_prompt` to change or disable
those mappings.

Inside `:CodexCLI` / `:CodexResume`:

| Key | Action |
| --- | --- |
| `<C-\><C-n>` | Leave terminal input mode so you can scroll or run Vim commands |
| `i` | Return to terminal input mode |
| `<C-u>` / `<C-d>` | Scroll earlier/later output after leaving terminal input mode |
| `G` | Jump back to the latest terminal output |
| `q` | Hide the Codex floating terminal after leaving terminal input mode |

If Codex uses the alternate screen and older output disappears, set
`cli.no_alt_screen = true`.

Codex CLI keeps its native terminal-mode shortcuts. The plugin does not bind
terminal-mode keys by default; set `cli.keymaps.terminal_escape` or
`cli.keymaps.terminal_close` if you want aliases such as `jk` or `<C-q>`.

## 🧬 Diff Review

When Codex chat returns a unified diff, the patch is parsed into files and
hunks before anything is applied.

Inside `:CodexDiff`:

| Key | Action |
| --- | --- |
| `a` | Accept current hunk |
| `r` | Reject current hunk |
| `A` | Accept current file |
| `R` | Reject current file |
| `p` | Preview accepted patch |
| `x` | Apply accepted hunks |
| `q` | Close review window |

## ⚙️ Configuration

```lua
require("codex").setup({
  codex_cmd = "codex",
  backend = "exec_json",
  ui = {
    layout = "right",
    width = 0.38,
    border = "rounded",
    keymaps = {
      focus_output = "<C-k>",
      focus_prompt = "<C-j>",
    },
  },
  keymaps = {
    visual_context = "<leader>aq",
  },
  exec = {
    skip_git_repo_check = true,
  },
  chat = {
    sandbox = "workspace-write",
  },
  cli = {
    terminal = "native",
    no_alt_screen = false,
    window = {
      layout = "center", -- "center" | "right"
      width = 0.9,
      height = 0.85,
      border = "rounded",
    },
    keymaps = {
      normal_close = "q",
      terminal_close = false,
      terminal_escape = false,
    },
  },
})
```

## 🗺️ Suggested Keymaps

```lua
vim.keymap.set("n", "<leader>aa", "<cmd>Codex<CR>", { desc = "Codex chat" })
vim.keymap.set("v", "<leader>aq", function()
  require("codex.ui").attach_selection()
end, { desc = "Attach selection to Codex" })
vim.keymap.set("n", "<leader>ad", "<cmd>CodexDiff<CR>", { desc = "Codex diff" })
vim.keymap.set("n", "<leader>ac", "<cmd>CodexCLI<CR>", { desc = "Codex CLI" })
```

## 🧪 Tests

```sh
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedDirectory tests { minimal_init = "tests/minimal_init.lua" }'
```

## 🧱 Status

This is an early implementation. The stable first backend uses
`codex exec --json`; experimental Codex app-server support can be added later
behind the same backend interface.
