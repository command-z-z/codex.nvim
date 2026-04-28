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
    require("codex").setup({
      edit = {
        mode = "manual", -- "manual" | "auto"
      },
    })
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
| `:CodexAsk [prompt]` | Ask about current context or visual selection |
| `:CodexEdit [prompt]` | Ask Codex to produce or apply a code edit |
| `:CodexDiff` | Open the pending hunk review UI |
| `:CodexApply` | Apply accepted hunks |
| `:CodexCLI [args...]` | Open the original Codex TUI |
| `:CodexResume [args...]` | Open `codex resume` in a terminal split |

Inside `:CodexCLI` / `:CodexResume`:

| Key | Action |
| --- | --- |
| `jk` / `<C-\><C-n>` | Leave terminal input mode so you can scroll or run Vim commands |
| `i` | Return to terminal input mode |
| `<C-u>` / `<C-d>` | Scroll earlier/later output after leaving terminal input mode |
| `G` | Jump back to the latest terminal output |
| `q` | Close the Codex terminal split after leaving terminal input mode |
| `<C-q>` | Close the Codex terminal split directly from terminal input mode |

If Codex uses the alternate screen and older output disappears, set
`cli.no_alt_screen = true`.

## 🧬 Diff Review

Manual edit mode runs Codex in `read-only` sandbox mode and asks for a unified
diff. The patch is parsed into files and hunks before anything is applied.

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
  },
  edit = {
    mode = "manual", -- "manual" | "auto"
    confirm = "hunk",
    sandbox = {
      manual = "read-only",
      auto = "workspace-write",
    },
  },
  cli = {
    terminal = "native",
    no_alt_screen = false,
  },
})
```

## 🗺️ Suggested Keymaps

```lua
vim.keymap.set("n", "<leader>aa", "<cmd>Codex<CR>", { desc = "Codex chat" })
vim.keymap.set({ "n", "v" }, "<leader>aq", "<cmd>CodexAsk<CR>", { desc = "Ask Codex" })
vim.keymap.set({ "n", "v" }, "<leader>ae", "<cmd>CodexEdit<CR>", { desc = "Edit with Codex" })
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
