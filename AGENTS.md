# Repository Guidelines

## Project Structure & Module Organization

This repository is a Neovim Lua plugin. Runtime entrypoints live in `plugin/codex.lua`, which registers plugin loading behavior, and implementation modules live under `lua/codex/`. Core modules include `config.lua`, `cli.lua`, `context.lua`, `diff.lua`, and `ui.lua`; UI-specific helpers are grouped in `lua/codex/ui/`. Tests are in `tests/` and use `tests/minimal_init.lua` to add this checkout plus local `plenary.nvim` and `nui.nvim` installs to Neovim's runtime path.

## Build, Test, and Development Commands

There is no build step; Neovim loads the Lua files directly.

Run the full test suite with:

```sh
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedDirectory tests { minimal_init = "tests/minimal_init.lua" }'
```

For local manual testing, install this checkout through your plugin manager with `dir = "/home/eugene/Desktop/MyRepo/codex.nvim"` and call `require("codex").setup()`. The plugin expects Neovim 0.10+, `plenary.nvim`, `nui.nvim`, and the `codex` CLI in `$PATH`.

## Coding Style & Naming Conventions

Use Lua module tables with `local M = {}` and return `M` from modules. Follow the existing four-space indentation style and prefer snake_case for functions, local variables, and option keys. Keep modules focused: command registration belongs in `lua/codex/init.lua`, defaults in `lua/codex/config.lua`, and interface behavior in `lua/codex/ui*.lua`. Prefer Neovim APIs and Plenary helpers already used in the codebase over introducing new dependencies.

## Testing Guidelines

Tests use Plenary's busted-style framework. Add or update `*_spec.lua` files in `tests/` near the behavior being changed, for example `diff_spec.lua` for patch parsing or `cli_spec.lua` for terminal behavior. Keep tests deterministic and avoid requiring a real Codex network session; mock jobs, buffers, or CLI results when possible. Run the full headless Neovim command before submitting changes.

## Commit & Pull Request Guidelines

Recent commits use concise imperative subjects such as `Refactor Codex UI helpers` and `Improve Codex UI and CLI workflow`. Keep commit titles short, capitalized, and focused on the user-visible or architectural change.

Pull requests should include a brief description, the commands run for verification, and screenshots or terminal notes for UI changes to panels, floating terminals, or diff review behavior. Link related issues when applicable and call out any dependency or configuration changes.

## Agent-Specific Instructions

Do not rewrite unrelated plugin behavior while addressing a narrow issue. Preserve existing user configuration keys where possible, and update `README.md` when commands, defaults, dependencies, or user-facing keymaps change.
