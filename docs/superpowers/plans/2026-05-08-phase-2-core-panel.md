# Phase 2: Core Panel + Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the core panel system — config validation, terminal providers (native/snacks/external), terminal orchestrator, and full init module — enabling `:Codex` panel toggle and all 12 commands that mirror `:ClaudeCode*`.

**Architecture:** `config.lua` validates and deep-merges user options; `utils.lua` provides shared helpers; `terminal.lua` selects from three providers based on availability; `init.lua` owns global state (`config`, `rpc`, `port`, `mention_queue`), wires providers to commands, and manages the @mention queue with timeout/expiry logic.

**Tech Stack:** Pure Lua, Neovim `vim.api`/`vim.loop`/`vim.uv`, optional `snacks.nvim`, busted (Lua 5.1 via `/usr/share/lua/5.1`), dkjson available for JSON. Phase 1 modules (`codex.transport`, `codex.rpc`, `codex.app_server`) are existing dependencies.

---

## File Map

| File | Role |
|------|------|
| `lua/codex/config.lua` | Defaults table + deep-merge + validation |
| `lua/codex/utils.lua` | `normalize_focus` helper (mirroring `claudecode.utils`) |
| `lua/codex/terminal/native.lua` | Built-in Neovim terminal provider |
| `lua/codex/terminal/snacks.lua` | snacks.nvim terminal provider |
| `lua/codex/terminal/external.lua` | External terminal launcher |
| `lua/codex/terminal.lua` | Provider orchestrator + `setup()`/`open()`/etc. |
| `lua/codex/init.lua` | Global state, `setup()`, command registration, mention queue |

**Vim mock note:** `tests/mocks/vim.lua` is missing `vim.cmd`, `vim.fn.termopen`, `vim.fn.jobstart`, `vim.fn.jobstop`, `vim.fn.systemlist`, `vim.fn.executable`, and `vim.defer_fn`. Each test file adds lightweight local stubs for functions it needs. Do NOT add these globally to the mock file — that risks breaking Phase 1 tests.

---

## Task 1: config.lua — defaults + validation

**Files:**
- Create: `lua/codex/config.lua`
- Create: `tests/unit/config_spec.lua`

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/config_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.config", function()
  local config

  before_each(function()
    package.loaded["codex.config"] = nil
    config = require("codex.config")
  end)

  describe("defaults", function()
    it("has codex_cmd = 'codex'", function()
      assert.equals("codex", config.defaults.codex_cmd)
    end)
    it("has auto_start = true", function()
      assert.is_true(config.defaults.auto_start)
    end)
    it("has terminal.provider = 'auto'", function()
      assert.equals("auto", config.defaults.terminal.provider)
    end)
    it("has terminal.split_side = 'right'", function()
      assert.equals("right", config.defaults.terminal.split_side)
    end)
    it("has terminal.split_width_percentage = 0.30", function()
      assert.equals(0.30, config.defaults.terminal.split_width_percentage)
    end)
    it("has approval.policy = 'prompt'", function()
      assert.equals("prompt", config.defaults.approval.policy)
    end)
    it("has approval.sandbox = 'workspace-write'", function()
      assert.equals("workspace-write", config.defaults.approval.sandbox)
    end)
    it("has queue_timeout = 5000", function()
      assert.equals(5000, config.defaults.queue_timeout)
    end)
  end)

  describe("apply()", function()
    it("returns defaults when called with empty table", function()
      local cfg = config.apply({})
      assert.equals("codex", cfg.codex_cmd)
      assert.equals("right", cfg.terminal.split_side)
      assert.equals("auto", cfg.terminal.provider)
    end)

    it("overrides top-level string key", function()
      local cfg = config.apply({ codex_cmd = "codex2" })
      assert.equals("codex2", cfg.codex_cmd)
    end)

    it("overrides top-level boolean key", function()
      local cfg = config.apply({ auto_start = false })
      assert.is_false(cfg.auto_start)
    end)

    it("deep merges terminal subtable, preserving other keys", function()
      local cfg = config.apply({ terminal = { provider = "native" } })
      assert.equals("native", cfg.terminal.provider)
      assert.equals("right", cfg.terminal.split_side)          -- preserved
      assert.equals(0.30, cfg.terminal.split_width_percentage) -- preserved
    end)

    it("deep merges approval subtable, preserving other keys", function()
      local cfg = config.apply({ approval = { policy = "auto-allow" } })
      assert.equals("auto-allow", cfg.approval.policy)
      assert.equals("workspace-write", cfg.approval.sandbox)  -- preserved
    end)

    it("does NOT mutate defaults on deep merge", function()
      config.apply({ terminal = { provider = "native" } })
      assert.equals("auto", config.defaults.terminal.provider)
    end)

    it("handles nil user_config gracefully", function()
      local cfg = config.apply(nil)
      assert.equals("codex", cfg.codex_cmd)
    end)
  end)

  describe("validate()", function()
    it("passes for fully valid config", function()
      assert.has_no.errors(function()
        config.validate(config.apply({}))
      end)
    end)

    it("errors on invalid terminal.provider", function()
      local ok, err = pcall(config.validate, { terminal = { provider = "bad_provider" } })
      assert.is_false(ok)
      assert.is_truthy(err:find("terminal%.provider"))
    end)

    it("errors on invalid approval.policy", function()
      local ok, err = pcall(config.validate, { approval = { policy = "bad" } })
      assert.is_false(ok)
      assert.is_truthy(err:find("approval%.policy"))
    end)

    it("errors on non-string codex_cmd", function()
      local ok, err = pcall(config.validate, { codex_cmd = 42 })
      assert.is_false(ok)
      assert.is_truthy(err:find("codex_cmd"))
    end)

    it("accepts all valid terminal providers", function()
      for _, p in ipairs({ "auto", "snacks", "native", "external", "none" }) do
        assert.has_no.errors(function()
          config.validate({ terminal = { provider = p } })
        end)
      end
    end)

    it("accepts all valid approval policies", function()
      for _, pol in ipairs({ "prompt", "auto-deny", "auto-allow" }) do
        assert.has_no.errors(function()
          config.validate({ approval = { policy = pol } })
        end)
      end
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eugene/Desktop/MyRepo/codex.nvim && busted tests/unit/config_spec.lua`

Expected: FAIL with `module 'codex.config' not found`

- [ ] **Step 3: Implement config.lua**

```lua
-- lua/codex/config.lua
local M = {}

M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  codex_cmd = "codex",
  env = {},
  log_level = "info",
  track_selection = true,
  visual_demotion_delay_ms = 50,
  focus_after_send = false,
  connection_wait_delay = 600,
  connection_timeout = 10000,
  queue_timeout = 5000,
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false,
    keep_terminal_focus = false,
    on_new_file_reject = "keep_empty",
    hunk_level_review = true,
  },
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_percentage = 0.30,
    snacks_win_opts = {},
    auto_close = true,
    cwd_provider = nil,
    git_repo_cwd = true,
    provider_opts = { external_terminal_cmd = nil },
  },
  approval = {
    policy = "prompt",
    sandbox = "workspace-write",
  },
  models = {},
}

local function deep_merge(base, override)
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.apply(user_config)
  return deep_merge(M.defaults, user_config or {})
end

local VALID_PROVIDERS = { auto = true, snacks = true, native = true, external = true, none = true }
local VALID_POLICIES = { prompt = true, ["auto-deny"] = true, ["auto-allow"] = true }

function M.validate(cfg)
  if cfg.codex_cmd ~= nil and type(cfg.codex_cmd) ~= "string" then
    error("codex_cmd must be a string, got " .. type(cfg.codex_cmd))
  end
  if cfg.terminal and cfg.terminal.provider ~= nil then
    if not VALID_PROVIDERS[cfg.terminal.provider] then
      error(
        "terminal.provider must be one of: auto, snacks, native, external, none. Got: "
          .. tostring(cfg.terminal.provider)
      )
    end
  end
  if cfg.approval and cfg.approval.policy ~= nil then
    if not VALID_POLICIES[cfg.approval.policy] then
      error(
        "approval.policy must be one of: prompt, auto-deny, auto-allow. Got: "
          .. tostring(cfg.approval.policy)
      )
    end
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/config_spec.lua`

Expected: All tests pass. Count: 18 assertions.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/config.lua tests/unit/config_spec.lua
git commit -m "feat(phase2): add config.lua with defaults, deep-merge, and validation"
```

---

## Task 2: utils.lua — normalize_focus

**Files:**
- Create: `lua/codex/utils.lua`
- Create: `tests/unit/utils_spec.lua`

Mirrors `claudecode.nvim/lua/claudecode/utils.lua` exactly. `normalize_focus(nil)` returns `true` (backward-compat default: focus=true). Only include what Phase 2 actually needs — YAGNI.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/utils_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.utils", function()
  local utils

  before_each(function()
    package.loaded["codex.utils"] = nil
    utils = require("codex.utils")
  end)

  describe("normalize_focus()", function()
    it("returns true when focus is nil (backward-compat default)", function()
      assert.is_true(utils.normalize_focus(nil))
    end)

    it("returns true when focus is true", function()
      assert.is_true(utils.normalize_focus(true))
    end)

    it("returns false when focus is false", function()
      assert.is_false(utils.normalize_focus(false))
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/unit/utils_spec.lua`

Expected: FAIL with `module 'codex.utils' not found`

- [ ] **Step 3: Implement utils.lua**

```lua
-- lua/codex/utils.lua
local M = {}

---Normalizes focus parameter, defaulting to true for backward compatibility.
---@param focus boolean? The focus parameter
---@return boolean
function M.normalize_focus(focus)
  if focus == nil then
    return true
  else
    return focus
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/utils_spec.lua`

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/utils.lua tests/unit/utils_spec.lua
git commit -m "feat(phase2): add utils.lua with normalize_focus (mirrors claudecode.utils)"
```

---

## Task 3: terminal/native.lua — built-in Neovim terminal

**Files:**
- Create: `lua/codex/terminal/native.lua`
- Create: `tests/unit/terminal_native_spec.lua`

Mirrors `claudecode.nvim/lua/claudecode/terminal/native.lua`. Module-level state: `bufnr`, `winid`, `jobid`. Uses `vim.cmd()` for split creation (same as claudecode.nvim). Provider interface (all functions are plain module-level, not methods):

| Function | Behavior |
|----------|----------|
| `open(cmd, opts)` | Create split + start terminal job; no-op if already valid |
| `close()` | Stop job, delete buffer, reset state |
| `simple_toggle(cmd, opts)` | Hide if visible; show hidden buffer; or open fresh |
| `focus_toggle(cmd, opts)` | Focus if terminal exists but not focused; open if not exists |
| `get_active_bufnr()` | Return bufnr or nil |
| `is_available()` | Always returns true |

`opts` keys used: `split_side` ("right"/"left"), `split_width_percentage` (float 0..1), `auto_close` (bool), `cwd` (string/nil).

**Vim mock gap:** `vim.cmd`, `vim.fn.termopen`, `vim.fn.jobstop` are not in `tests/mocks/vim.lua`. Stub them in `before_each`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/terminal_native_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.terminal.native", function()
  local native
  local cmd_calls, termopen_calls, jobstop_calls

  before_each(function()
    package.loaded["codex.terminal.native"] = nil
    package.loaded["codex.utils"] = nil

    cmd_calls = {}
    termopen_calls = {}
    jobstop_calls = {}

    -- stub missing vim functions
    _G.vim.cmd = function(cmd) table.insert(cmd_calls, cmd) end
    _G.vim.fn.termopen = function(cmd_arg, _opts)
      table.insert(termopen_calls, cmd_arg)
      return 99  -- fake jobid
    end
    _G.vim.fn.jobstop = function(id) table.insert(jobstop_calls, id) end

    -- make nvim_get_current_win return a non-terminal window
    _G.vim.api._current_window = 1000

    native = require("codex.terminal.native")
  end)

  it("is_available() returns true", function()
    assert.is_true(native.is_available())
  end)

  it("get_active_bufnr() returns nil before open()", function()
    assert.is_nil(native.get_active_bufnr())
  end)

  describe("open()", function()
    it("creates a new buffer and starts terminal", function()
      native.open("codex", { split_side = "right", split_width_percentage = 0.30 })
      assert.is_not_nil(native.get_active_bufnr())
      assert.equals(1, #termopen_calls)
    end)

    it("passes command string to termopen", function()
      native.open("mycodex --flag", {})
      assert.equals(1, #termopen_calls)
      -- termopen receives a list or string based on spaces
      local cmd_arg = termopen_calls[1]
      local full = type(cmd_arg) == "table" and table.concat(cmd_arg, " ") or cmd_arg
      assert.is_truthy(full:find("mycodex"))
    end)

    it("issues vim.cmd for vsplit", function()
      native.open("codex", { split_side = "right" })
      assert.is_true(#cmd_calls >= 1)
    end)

    it("is a no-op when terminal is already open", function()
      native.open("codex", {})
      local bufnr_first = native.get_active_bufnr()
      native.open("codex", {})  -- second call
      assert.equals(bufnr_first, native.get_active_bufnr())
      assert.equals(1, #termopen_calls)  -- only opened once
    end)
  end)

  describe("close()", function()
    it("resets state so get_active_bufnr() returns nil", function()
      native.open("codex", {})
      assert.is_not_nil(native.get_active_bufnr())
      native.close()
      assert.is_nil(native.get_active_bufnr())
    end)

    it("stops the terminal job", function()
      native.open("codex", {})
      native.close()
      assert.equals(1, #jobstop_calls)
      assert.equals(99, jobstop_calls[1])
    end)

    it("is safe to call when not open", function()
      assert.has_no.errors(function()
        native.close()
      end)
    end)
  end)

  describe("simple_toggle()", function()
    it("opens terminal when not open", function()
      native.simple_toggle("codex", {})
      assert.is_not_nil(native.get_active_bufnr())
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/unit/terminal_native_spec.lua`

Expected: FAIL with `module 'codex.terminal.native' not found`

- [ ] **Step 3: Implement terminal/native.lua**

```lua
-- lua/codex/terminal/native.lua
local utils = require("codex.utils")

local M = {}

local bufnr = nil
local winid = nil
local jobid = nil

local function cleanup_state()
  bufnr = nil
  winid = nil
  jobid = nil
end

local function is_valid()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    cleanup_state()
    return false
  end
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    -- buffer valid but no window: check if any window shows it
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      if vim.api.nvim_win_get_buf(w) == bufnr then
        winid = w
        return true
      end
    end
    return true  -- buffer valid even if not visible
  end
  return true
end

local function hide_terminal()
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, false)
    winid = nil
  end
end

function M.is_available()
  return true
end

function M.get_active_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end
  return nil
end

function M.open(cmd_string, opts)
  opts = opts or {}
  local focus = utils.normalize_focus(opts.focus)
  local split_side = opts.split_side or "right"
  local split_pct = opts.split_width_percentage or 0.30
  local auto_close = opts.auto_close ~= false

  if is_valid() then
    if focus and winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_set_current_win(winid)
      vim.cmd("startinsert")
    end
    return
  end

  local width = math.floor(vim.o.columns * split_pct)
  local placement = (split_side == "left") and "topleft " or "botright "
  vim.cmd(placement .. width .. "vsplit")

  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_call(new_winid, function()
    vim.cmd("enew")
  end)

  local term_cmd
  if cmd_string:find(" ", 1, true) then
    term_cmd = vim.split(cmd_string, " ", { plain = true, trimempty = false })
  else
    term_cmd = { cmd_string }
  end

  local term_opts = {
    env = opts.env or {},
    cwd = opts.cwd,
  }
  if auto_close then
    term_opts.on_exit = function(jid, _, _)
      vim.schedule(function()
        if jid == jobid then
          cleanup_state()
        end
      end)
    end
  end

  jobid = vim.fn.termopen(term_cmd, term_opts)
  bufnr = vim.api.nvim_get_current_buf()
  winid = new_winid

  if not focus then
    local original_win = vim.api.nvim_get_current_win()
    if original_win == winid then
      -- return to previous window stored before cmd
    end
  end
end

function M.close()
  if jobid then
    pcall(vim.fn.jobstop, jobid)
    jobid = nil
  end
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  cleanup_state()
end

function M.simple_toggle(cmd_string, opts)
  if is_valid() then
    local buf_has_window = false
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == bufnr then
        buf_has_window = true
        hide_terminal()
        return
      end
    end
    -- buffer valid but hidden: show it
    if not buf_has_window then
      local split_side = (opts or {}).split_side or "right"
      local split_pct = (opts or {}).split_width_percentage or 0.30
      local width = math.floor(vim.o.columns * split_pct)
      local placement = (split_side == "left") and "topleft " or "botright "
      vim.cmd(placement .. width .. "vsplit")
      winid = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(winid, bufnr)
    end
  else
    M.open(cmd_string, opts)
  end
end

function M.focus_toggle(cmd_string, opts)
  if not is_valid() then
    M.open(cmd_string, opts)
    return
  end
  local current_win = vim.api.nvim_get_current_win()
  if winid and current_win == winid then
    hide_terminal()
  else
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_set_current_win(winid)
    else
      M.open(cmd_string, opts)
    end
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/terminal_native_spec.lua`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/terminal/native.lua tests/unit/terminal_native_spec.lua
git commit -m "feat(phase2): add terminal/native.lua built-in terminal provider"
```

---

## Task 4: terminal/snacks.lua — snacks.nvim adapter

**Files:**
- Create: `lua/codex/terminal/snacks.lua`
- Create: `tests/unit/terminal_snacks_spec.lua`

Wraps `snacks.terminal`. Uses `pcall(require, "snacks")` so tests can inject a fake or block it. Interface: same as native.lua plus `_get_terminal_for_test()`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/terminal_snacks_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.terminal.snacks", function()
  local snacks_mod

  -- helper: reload module fresh
  local function reload()
    package.loaded["codex.terminal.snacks"] = nil
    return require("codex.terminal.snacks")
  end

  describe("without snacks.nvim", function()
    before_each(function()
      package.loaded["snacks"] = nil
      package.preload["snacks"] = function() error("snacks not installed") end
      snacks_mod = reload()
    end)
    after_each(function()
      package.preload["snacks"] = nil
    end)

    it("is_available() returns false", function()
      assert.is_false(snacks_mod.is_available())
    end)

    it("open() does nothing and does not error", function()
      assert.has_no.errors(function()
        snacks_mod.open("codex", {})
      end)
    end)

    it("get_active_bufnr() returns nil", function()
      assert.is_nil(snacks_mod.get_active_bufnr())
    end)

    it("close() does not error", function()
      assert.has_no.errors(function()
        snacks_mod.close()
      end)
    end)
  end)

  describe("with snacks mock", function()
    local fake_terminal_instance
    local toggle_calls

    before_each(function()
      toggle_calls = {}
      fake_terminal_instance = {
        buf = 77,
        win = 88,
        is_hidden = function() return false end,
        hide = function() end,
        close = function() fake_terminal_instance.buf = nil end,
      }
      local fake_snacks = {
        terminal = {
          get = function() return fake_terminal_instance end,
          toggle = function(cmd, _opts)
            table.insert(toggle_calls, cmd)
            return fake_terminal_instance
          end,
        },
      }
      package.loaded["snacks"] = fake_snacks
      package.preload["snacks"] = nil
      snacks_mod = reload()
    end)

    after_each(function()
      package.loaded["snacks"] = nil
    end)

    it("is_available() returns true", function()
      assert.is_true(snacks_mod.is_available())
    end)

    it("open() calls snacks.terminal.toggle with the command", function()
      snacks_mod.open("codex", {})
      assert.equals(1, #toggle_calls)
      assert.equals("codex", toggle_calls[1])
    end)

    it("get_active_bufnr() returns terminal buf after open()", function()
      snacks_mod.open("codex", {})
      assert.equals(77, snacks_mod.get_active_bufnr())
    end)

    it("get_active_bufnr() returns nil before open()", function()
      -- not opened yet in this before_each
      assert.is_nil(snacks_mod.get_active_bufnr())
    end)

    it("simple_toggle() calls snacks.terminal.toggle", function()
      snacks_mod.simple_toggle("codex", {})
      assert.equals(1, #toggle_calls)
    end)

    it("_get_terminal_for_test() returns the stored terminal", function()
      snacks_mod.open("codex", {})
      assert.equals(fake_terminal_instance, snacks_mod._get_terminal_for_test())
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/unit/terminal_snacks_spec.lua`

Expected: FAIL with `module 'codex.terminal.snacks' not found`

- [ ] **Step 3: Implement terminal/snacks.lua**

```lua
-- lua/codex/terminal/snacks.lua
local snacks_ok, Snacks = pcall(require, "snacks")

local M = {}

local terminal = nil

local function build_snacks_opts(opts)
  opts = opts or {}
  local split_side = opts.split_side or "right"
  local split_pct = opts.split_width_percentage or 0.30
  local snacks_win_opts = opts.snacks_win_opts or {}

  local position
  if split_side == "left" then
    position = "left"
  elseif split_side == "below" or split_side == "above" then
    position = "bottom"
  else
    position = "right"
  end

  return {
    win = vim.tbl_extend("force", {
      position = position,
      width = (position == "right" or position == "left") and split_pct or nil,
      height = (position == "bottom") and split_pct or nil,
    }, snacks_win_opts),
  }
end

function M.is_available()
  return snacks_ok
    and Snacks ~= nil
    and type(Snacks) == "table"
    and type(Snacks.terminal) == "table"
end

function M.get_active_bufnr()
  if terminal and terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
    return terminal.buf
  end
  return nil
end

function M.open(cmd, opts)
  if not M.is_available() then
    return
  end
  terminal = Snacks.terminal.toggle(cmd, build_snacks_opts(opts))
end

function M.close()
  if not M.is_available() then
    return
  end
  if terminal then
    terminal:close()
    terminal = nil
  end
end

function M.simple_toggle(cmd, opts)
  if not M.is_available() then
    return
  end
  terminal = Snacks.terminal.toggle(cmd, build_snacks_opts(opts))
end

function M.focus_toggle(cmd, opts)
  if not M.is_available() then
    return
  end
  if terminal and not terminal:is_hidden() then
    local current = vim.api.nvim_get_current_win()
    if terminal.win and vim.api.nvim_win_is_valid(terminal.win) and current == terminal.win then
      terminal:hide()
      return
    end
    if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
      vim.api.nvim_set_current_win(terminal.win)
      return
    end
  end
  terminal = Snacks.terminal.toggle(cmd, build_snacks_opts(opts))
end

function M._get_terminal_for_test()
  return terminal
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/terminal_snacks_spec.lua`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/terminal/snacks.lua tests/unit/terminal_snacks_spec.lua
git commit -m "feat(phase2): add terminal/snacks.lua snacks.nvim terminal adapter"
```

---

## Task 5: terminal/external.lua — external terminal launcher

**Files:**
- Create: `lua/codex/terminal/external.lua`
- Create: `tests/unit/terminal_external_spec.lua`

Launches an external terminal application. `is_available(opts)` takes opts (unlike other providers) because availability depends on config. `get_active_bufnr()` always returns nil. `ensure_visible()` is a no-op.

`opts.provider_opts.external_terminal_cmd`:
- String with `%s` placeholder: `"alacritty -e %s"` → `string.format(tmpl, cmd)`
- Function: `function(cmd) return {"alacritty", "-e", cmd} end`

**Vim mock gap:** `vim.fn.jobstart` and `vim.fn.jobstop` must be stubbed in before_each.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/terminal_external_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.terminal.external", function()
  local external
  local jobstart_calls, jobstop_calls

  before_each(function()
    package.loaded["codex.terminal.external"] = nil
    jobstart_calls = {}
    jobstop_calls = {}
    _G.vim.fn.jobstart = function(cmd_arg, _opts)
      table.insert(jobstart_calls, cmd_arg)
      return 55
    end
    _G.vim.fn.jobstop = function(id) table.insert(jobstop_calls, id) end
    external = require("codex.terminal.external")
  end)

  describe("is_available()", function()
    it("returns true when external_terminal_cmd is a string", function()
      assert.is_true(external.is_available({ provider_opts = { external_terminal_cmd = "alacritty -e %s" } }))
    end)

    it("returns true when external_terminal_cmd is a function", function()
      assert.is_true(external.is_available({ provider_opts = { external_terminal_cmd = function() end } }))
    end)

    it("returns false when external_terminal_cmd is nil", function()
      assert.is_false(external.is_available({ provider_opts = {} }))
    end)

    it("returns false when provider_opts is nil", function()
      assert.is_false(external.is_available({}))
    end)
  end)

  it("get_active_bufnr() always returns nil", function()
    assert.is_nil(external.get_active_bufnr())
  end)

  describe("open() with string template", function()
    it("passes formatted command to jobstart", function()
      external.open("codex", { provider_opts = { external_terminal_cmd = "alacritty -e %s" } })
      assert.equals(1, #jobstart_calls)
      assert.equals("alacritty -e codex", jobstart_calls[1])
    end)

    it("does not start a second job if already running", function()
      external.open("codex", { provider_opts = { external_terminal_cmd = "alacritty -e %s" } })
      external.open("codex", { provider_opts = { external_terminal_cmd = "alacritty -e %s" } })
      assert.equals(1, #jobstart_calls)
    end)
  end)

  describe("open() with function template", function()
    it("calls the function with cmd and passes result to jobstart", function()
      local fn_arg = nil
      local fn = function(c) fn_arg = c; return { "alacritty", "-e", c } end
      external.open("codex", { provider_opts = { external_terminal_cmd = fn } })
      assert.equals("codex", fn_arg)
      assert.equals(1, #jobstart_calls)
      assert.same({ "alacritty", "-e", "codex" }, jobstart_calls[1])
    end)
  end)

  describe("close()", function()
    it("stops the job and resets state", function()
      external.open("codex", { provider_opts = { external_terminal_cmd = "alacritty -e %s" } })
      external.close()
      assert.equals(1, #jobstop_calls)
      assert.equals(55, jobstop_calls[1])
    end)

    it("is safe to call when not open", function()
      assert.has_no.errors(function() external.close() end)
    end)

    it("allows re-open after close", function()
      external.open("codex", { provider_opts = { external_terminal_cmd = "alacritty -e %s" } })
      external.close()
      external.open("codex", { provider_opts = { external_terminal_cmd = "alacritty -e %s" } })
      assert.equals(2, #jobstart_calls)
    end)
  end)

  it("ensure_visible() is a no-op", function()
    assert.has_no.errors(function() external.ensure_visible() end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/unit/terminal_external_spec.lua`

Expected: FAIL with `module 'codex.terminal.external' not found`

- [ ] **Step 3: Implement terminal/external.lua**

```lua
-- lua/codex/terminal/external.lua
local M = {}

local jobid = nil

function M.is_available(opts)
  opts = opts or {}
  local ext_cmd = opts.provider_opts and opts.provider_opts.external_terminal_cmd
  return ext_cmd ~= nil
end

function M.get_active_bufnr()
  return nil
end

function M.open(cmd, opts)
  if jobid then
    return  -- already running
  end
  opts = opts or {}
  local ext_cmd = opts.provider_opts and opts.provider_opts.external_terminal_cmd
  if not ext_cmd then
    vim.notify("codex: external_terminal_cmd not configured", vim.log.levels.WARN)
    return
  end

  local launch_cmd
  if type(ext_cmd) == "function" then
    launch_cmd = ext_cmd(cmd)
  else
    launch_cmd = string.format(ext_cmd, cmd)
  end

  jobid = vim.fn.jobstart(launch_cmd, { detach = true })
end

function M.close()
  if jobid then
    pcall(vim.fn.jobstop, jobid)
    jobid = nil
  end
end

function M.simple_toggle(cmd, opts)
  if jobid then
    M.close()
  else
    M.open(cmd, opts)
  end
end

function M.focus_toggle(cmd, opts)
  -- external terminals can't be focused programmatically; just open
  M.open(cmd, opts)
end

function M.ensure_visible()
  -- no-op: cannot control external window position
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/terminal_external_spec.lua`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/terminal/external.lua tests/unit/terminal_external_spec.lua
git commit -m "feat(phase2): add terminal/external.lua external terminal launcher"
```

---

## Task 6: terminal.lua — provider orchestrator

**Files:**
- Create: `lua/codex/terminal.lua`
- Create: `tests/unit/terminal_spec.lua`

Selects and delegates to one provider. All public functions are plain module-level (no `self`).

**Provider resolution for `"auto"`:**
1. snacks if `snacks.is_available()` → `"snacks"`
2. else native → `"native"`

**All providers must implement:** `open(cmd, opts)`, `close()`, `simple_toggle(cmd, opts)`, `focus_toggle(cmd, opts)`, `get_active_bufnr()`, `is_available()`

The orchestrator calls them as `provider.open(cmd, opts)` (not `provider:open(...)`).

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/terminal_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.terminal", function()
  local terminal
  local mock_native, mock_snacks, mock_external

  local function make_mock(name, available)
    local m = { _name = name, _calls = {} }
    m.is_available = function() return available end
    m.open = function(cmd, opts) table.insert(m._calls, { "open", cmd }) end
    m.close = function() table.insert(m._calls, { "close" }) end
    m.simple_toggle = function(cmd, opts) table.insert(m._calls, { "simple_toggle", cmd }) end
    m.focus_toggle = function(cmd, opts) table.insert(m._calls, { "focus_toggle", cmd }) end
    m.get_active_bufnr = function() return name == "native" and 42 or nil end
    return m
  end

  before_each(function()
    package.loaded["codex.terminal"] = nil
    package.loaded["codex.terminal.native"] = nil
    package.loaded["codex.terminal.snacks"] = nil
    package.loaded["codex.terminal.external"] = nil

    mock_native   = make_mock("native", true)
    mock_snacks   = make_mock("snacks", false)
    mock_external = make_mock("external", false)

    package.loaded["codex.terminal.native"]   = mock_native
    package.loaded["codex.terminal.snacks"]   = mock_snacks
    package.loaded["codex.terminal.external"] = mock_external

    terminal = require("codex.terminal")
  end)

  describe("setup() — provider resolution", function()
    it("selects native when provider='native'", function()
      terminal.setup({ terminal = { provider = "native" }, codex_cmd = "codex" })
      assert.equals("native", terminal._get_active_provider_name())
    end)

    it("selects snacks when provider='snacks' and snacks is available", function()
      mock_snacks.is_available = function() return true end
      terminal.setup({ terminal = { provider = "snacks" }, codex_cmd = "codex" })
      assert.equals("snacks", terminal._get_active_provider_name())
    end)

    it("falls back to native when provider='snacks' but snacks unavailable", function()
      mock_snacks.is_available = function() return false end
      terminal.setup({ terminal = { provider = "snacks" }, codex_cmd = "codex" })
      assert.equals("native", terminal._get_active_provider_name())
    end)

    it("auto selects snacks when available", function()
      mock_snacks.is_available = function() return true end
      terminal.setup({ terminal = { provider = "auto" }, codex_cmd = "codex" })
      assert.equals("snacks", terminal._get_active_provider_name())
    end)

    it("auto falls back to native when snacks unavailable", function()
      mock_snacks.is_available = function() return false end
      terminal.setup({ terminal = { provider = "auto" }, codex_cmd = "codex" })
      assert.equals("native", terminal._get_active_provider_name())
    end)

    it("selects none provider when provider='none'", function()
      terminal.setup({ terminal = { provider = "none" }, codex_cmd = "codex" })
      assert.equals("none", terminal._get_active_provider_name())
    end)
  end)

  describe("delegating to active provider", function()
    before_each(function()
      terminal.setup({ terminal = { provider = "native" }, codex_cmd = "codex" })
    end)

    it("open() calls provider.open with codex_cmd", function()
      terminal.open()
      assert.equals(1, #mock_native._calls)
      assert.equals("open", mock_native._calls[1][1])
      assert.equals("codex", mock_native._calls[1][2])
    end)

    it("close() calls provider.close", function()
      terminal.close()
      assert.equals("close", mock_native._calls[1][1])
    end)

    it("simple_toggle() calls provider.simple_toggle with codex_cmd", function()
      terminal.simple_toggle()
      assert.equals("simple_toggle", mock_native._calls[1][1])
      assert.equals("codex", mock_native._calls[1][2])
    end)

    it("focus_toggle() calls provider.focus_toggle", function()
      terminal.focus_toggle()
      assert.equals("focus_toggle", mock_native._calls[1][1])
    end)

    it("get_active_terminal_bufnr() returns provider value", function()
      assert.equals(42, terminal.get_active_terminal_bufnr())
    end)
  end)

  it("none provider: all operations are no-ops", function()
    terminal.setup({ terminal = { provider = "none" }, codex_cmd = "codex" })
    assert.has_no.errors(function()
      terminal.open()
      terminal.close()
      terminal.simple_toggle()
      terminal.focus_toggle()
    end)
    assert.is_nil(terminal.get_active_terminal_bufnr())
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/unit/terminal_spec.lua`

Expected: FAIL with `module 'codex.terminal' not found`

- [ ] **Step 3: Implement terminal.lua**

```lua
-- lua/codex/terminal.lua
local M = {}

local active_provider = nil
local active_provider_name = nil
local active_config = nil

local NOOP_PROVIDER = {
  is_available = function() return true end,
  open = function() end,
  close = function() end,
  simple_toggle = function() end,
  focus_toggle = function() end,
  get_active_bufnr = function() return nil end,
}

local function resolve_provider(cfg)
  local terminal_cfg = cfg.terminal or {}
  local p = terminal_cfg.provider or "auto"

  if p == "none" then
    return NOOP_PROVIDER, "none"
  end

  if p == "external" then
    return require("codex.terminal.external"), "external"
  end

  local snacks = require("codex.terminal.snacks")
  local native = require("codex.terminal.native")

  if p == "snacks" then
    if snacks.is_available() then
      return snacks, "snacks"
    end
    vim.notify(
      "codex: snacks provider requested but snacks.nvim is not available, falling back to native",
      vim.log.levels.WARN
    )
    return native, "native"
  end

  if p == "native" then
    return native, "native"
  end

  -- "auto"
  if snacks.is_available() then
    return snacks, "snacks"
  end
  return native, "native"
end

function M.setup(config)
  active_config = config
  active_provider, active_provider_name = resolve_provider(config)
end

local function get_cmd()
  return active_config and active_config.codex_cmd or "codex"
end

local function get_opts()
  return active_config and active_config.terminal or {}
end

function M.open()
  if not active_provider then return end
  active_provider.open(get_cmd(), get_opts())
end

function M.close()
  if not active_provider then return end
  active_provider.close()
end

function M.simple_toggle()
  if not active_provider then return end
  active_provider.simple_toggle(get_cmd(), get_opts())
end

function M.focus_toggle()
  if not active_provider then return end
  active_provider.focus_toggle(get_cmd(), get_opts())
end

function M.get_active_terminal_bufnr()
  if not active_provider then return nil end
  return active_provider.get_active_bufnr()
end

-- test helper
function M._get_active_provider_name()
  return active_provider_name
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/terminal_spec.lua`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/terminal.lua tests/unit/terminal_spec.lua
git commit -m "feat(phase2): add terminal.lua provider orchestrator"
```

---

## Task 7: init.lua — setup(), commands, @mention queue

**Files:**
- Modify: `lua/codex/init.lua` (replace Phase 0 stub — full rewrite of file)
- Create: `tests/unit/init_spec.lua`

`init.lua` owns global plugin state and registers all 12 commands.

**State table:**

```lua
M.state = {
  config = nil,         -- applied + validated config
  rpc = nil,            -- codex.rpc instance (set when connected)
  port = nil,           -- connected port number
  initialized = false,
  mention_queue = {},   -- {text, expires_at} items
  mention_timer = nil,  -- handle from vim.defer_fn
  connection_timer = nil,
}
```

**@mention queue rules:**
- If connected: debounce 50ms, then send items with 25ms gap between each
- If not connected: items expire at `now + 5000ms`; queue cleared after `queue_timeout` ms
- `enqueue_mention(text)` is the public entry point

**Commands registered:**

| Command | Nargs | Behavior |
|---------|-------|----------|
| `:Codex [--resume\|--continue]` | `?` | `simple_toggle()` or open with flag |
| `:CodexFocus` | 0 | `focus_toggle()` |
| `:CodexOpen` | 0 | `terminal.open()` |
| `:CodexClose` | 0 | `terminal.close()` |
| `:CodexAdd <file> [start] [end]` | `+` | `enqueue_mention` with file path |
| `:CodexSend` | range | stub (Phase 3) |
| `:CodexDiffAccept` | 0 | stub (Phase 4) |
| `:CodexDiffDeny` | 0 | stub (Phase 4) |
| `:CodexSelectModel` | 0 | stub (Phase 6) |
| `:CodexStart` | 0 | `start_server()` |
| `:CodexStop` | 0 | close rpc + stop app_server |
| `:CodexStatus` | 0 | notify connection status |

**Vim mock gap:** `vim.defer_fn` is not in the mock. Stub it in before_each.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/init_spec.lua
local test_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]+/[^/]+$")
dofile(test_dir .. "/busted_setup.lua")

describe("codex.init", function()
  local codex
  local registered_cmds, deferred_calls

  before_each(function()
    registered_cmds = {}
    deferred_calls = {}

    -- stub missing vim functions
    _G.vim.defer_fn = function(fn, ms) table.insert(deferred_calls, { fn = fn, ms = ms }) end

    -- spy on nvim_create_user_command to track registrations
    local original_create_cmd = _G.vim.api.nvim_create_user_command
    _G.vim.api.nvim_create_user_command = function(name, cb, opts)
      registered_cmds[name] = { cb = cb, opts = opts }
      return original_create_cmd(name, cb, opts)
    end

    -- stub all plugin dependencies
    package.loaded["codex.init"] = nil
    for _, mod in ipairs({ "codex.config", "codex.terminal", "codex.app_server", "codex.rpc" }) do
      package.loaded[mod] = nil
    end

    package.preload["codex.config"] = function()
      return {
        defaults = {},
        apply = function(u)
          return vim.tbl_extend("force", {
            codex_cmd = "codex",
            auto_start = false,  -- disable auto-start in tests
            terminal = { provider = "native" },
            approval = { policy = "prompt" },
            queue_timeout = 5000,
            connection_wait_delay = 600,
            connection_timeout = 10000,
          }, u or {})
        end,
        validate = function() end,
      }
    end
    package.preload["codex.terminal"] = function()
      return {
        setup = function() end,
        open = function() end,
        close = function() end,
        simple_toggle = function() end,
        focus_toggle = function() end,
        get_active_terminal_bufnr = function() return nil end,
      }
    end
    package.preload["codex.app_server"] = function()
      return {
        ensure = function(cb) if cb then cb() end end,
        stop = function() end,
        url = function() return "ws://127.0.0.1:11111" end,
      }
    end
    package.preload["codex.rpc"] = function()
      return {
        connect = function() return { close = function() end, notify = function() end } end,
      }
    end

    codex = require("codex.init")
  end)

  after_each(function()
    for _, mod in ipairs({ "codex.config", "codex.terminal", "codex.app_server", "codex.rpc" }) do
      package.preload[mod] = nil
    end
  end)

  describe("setup()", function()
    it("sets initialized = true", function()
      codex.setup({})
      assert.is_true(codex.state.initialized)
    end)

    it("stores config in state", function()
      codex.setup({ codex_cmd = "mycodex" })
      assert.equals("mycodex", codex.state.config.codex_cmd)
    end)

    it("can be called twice without error", function()
      assert.has_no.errors(function()
        codex.setup({})
        codex.setup({})
      end)
    end)
  end)

  describe("command registration", function()
    before_each(function()
      codex.setup({})
    end)

    local expected_commands = {
      "Codex", "CodexFocus", "CodexOpen", "CodexClose",
      "CodexAdd", "CodexSend", "CodexDiffAccept", "CodexDiffDeny",
      "CodexSelectModel", "CodexStart", "CodexStop", "CodexStatus",
    }

    for _, name in ipairs(expected_commands) do
      it("registers " .. name, function()
        assert.is_not_nil(registered_cmds[name], name .. " should be registered")
      end)
    end
  end)

  describe("enqueue_mention()", function()
    it("adds item to mention_queue", function()
      codex.setup({})
      codex.enqueue_mention("@hello")
      assert.equals(1, #codex.state.mention_queue)
      assert.equals("@hello", codex.state.mention_queue[1].text)
    end)

    it("sets expires_at on enqueued item", function()
      codex.setup({})
      codex.enqueue_mention("test")
      assert.is_not_nil(codex.state.mention_queue[1].expires_at)
    end)

    it("enqueues multiple items", function()
      codex.setup({})
      codex.enqueue_mention("a")
      codex.enqueue_mention("b")
      assert.equals(2, #codex.state.mention_queue)
    end)
  end)

  describe("initial state", function()
    it("rpc is nil before connection", function()
      codex.setup({})
      assert.is_nil(codex.state.rpc)
    end)

    it("mention_queue starts empty", function()
      codex.setup({})
      assert.equals(0, #codex.state.mention_queue)
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/unit/init_spec.lua`

Expected: FAIL (stub init.lua doesn't expose `state` or `enqueue_mention`)

- [ ] **Step 3: Implement init.lua (replace stub)**

```lua
-- lua/codex/init.lua
local M = {}

M.state = {
  config = nil,
  rpc = nil,
  port = nil,
  initialized = false,
  mention_queue = {},
  mention_timer = nil,
  connection_timer = nil,
}

local function is_connected()
  return M.state.rpc ~= nil
end

local function flush_mentions()
  if not is_connected() or #M.state.mention_queue == 0 then
    return
  end
  local rpc = M.state.rpc
  local now = vim.loop.now()
  local queue = {}
  for _, item in ipairs(M.state.mention_queue) do
    if item.expires_at > now then
      table.insert(queue, item)
    end
  end
  M.state.mention_queue = {}

  local function send_next(i)
    if i > #queue then return end
    rpc:notify("$/codex/mention", { text = queue[i].text })
    vim.defer_fn(function() send_next(i + 1) end, 25)
  end
  send_next(1)
end

local function schedule_flush()
  M.state.mention_timer = vim.defer_fn(flush_mentions, 50)
end

function M.enqueue_mention(text)
  local timeout = (M.state.config and M.state.config.queue_timeout) or 5000
  table.insert(M.state.mention_queue, {
    text = text,
    expires_at = vim.loop.now() + 5000,
  })
  if is_connected() then
    schedule_flush()
  else
    vim.defer_fn(function()
      local now = vim.loop.now()
      local fresh = {}
      for _, item in ipairs(M.state.mention_queue) do
        if item.expires_at > now then
          table.insert(fresh, item)
        end
      end
      M.state.mention_queue = fresh
    end, timeout)
  end
end

local function on_connected(rpc)
  M.state.rpc = rpc
  if #M.state.mention_queue > 0 then
    schedule_flush()
  end
end

local function start_server()
  local app_server = require("codex.app_server")
  local rpc_mod = require("codex.rpc")

  app_server.ensure(function()
    local url = app_server.url()
    local rpc = rpc_mod.connect(url, {
      on_notification = function(_method, _params)
        -- Phase 4/5: handlers registered here
      end,
      on_request = function(_method, _params, _respond)
        -- Phase 5: approval handler
      end,
    })
    on_connected(rpc)
  end)
end

local function create_commands()
  local terminal = require("codex.terminal")

  vim.api.nvim_create_user_command("Codex", function(args)
    local arg = (args.args or ""):match("^%s*(.-)%s*$")
    if arg == "--resume" or arg == "--continue" then
      -- Store flag for terminal open to read (Phase 3 integration)
      M.state._open_flag = arg
    else
      M.state._open_flag = nil
    end
    terminal.simple_toggle()
  end, { nargs = "?", desc = "Toggle Codex panel" })

  vim.api.nvim_create_user_command("CodexFocus", function()
    terminal.focus_toggle()
  end, { desc = "Smart focus/unfocus Codex panel" })

  vim.api.nvim_create_user_command("CodexOpen", function()
    terminal.open()
  end, { desc = "Open Codex panel" })

  vim.api.nvim_create_user_command("CodexClose", function()
    terminal.close()
  end, { desc = "Close Codex panel" })

  vim.api.nvim_create_user_command("CodexAdd", function(args)
    local parts = vim.split(args.args, "%s+", { trimempty = true })
    local file = parts[1]
    if not file or file == "" then
      vim.notify("CodexAdd: file argument required", vim.log.levels.ERROR)
      return
    end
    local text = file
    if parts[2] then
      text = text .. ":" .. parts[2]
      if parts[3] then text = text .. "-" .. parts[3] end
    end
    M.enqueue_mention(text)
  end, { nargs = "+", complete = "file", desc = "Add file/range to Codex context" })

  vim.api.nvim_create_user_command("CodexSend", function()
    -- Phase 3: visual_commands.lua will handle this
    vim.notify("CodexSend: implemented in Phase 3", vim.log.levels.INFO)
  end, { range = true, desc = "Send selection to Codex" })

  vim.api.nvim_create_user_command("CodexDiffAccept", function()
    -- Phase 4: diff accept
    vim.notify("CodexDiffAccept: implemented in Phase 4", vim.log.levels.INFO)
  end, { desc = "Accept pending Codex diff" })

  vim.api.nvim_create_user_command("CodexDiffDeny", function()
    -- Phase 4: diff deny
    vim.notify("CodexDiffDeny: implemented in Phase 4", vim.log.levels.INFO)
  end, { desc = "Deny pending Codex diff" })

  vim.api.nvim_create_user_command("CodexSelectModel", function()
    -- Phase 6: model selection UI
    vim.notify("CodexSelectModel: implemented in Phase 6", vim.log.levels.INFO)
  end, { desc = "Select Codex model" })

  vim.api.nvim_create_user_command("CodexStart", function()
    start_server()
    vim.notify("codex: starting app-server...", vim.log.levels.INFO)
  end, { desc = "Start Codex app-server" })

  vim.api.nvim_create_user_command("CodexStop", function()
    if M.state.rpc then
      M.state.rpc:close()
      M.state.rpc = nil
    end
    require("codex.app_server").stop()
    vim.notify("codex: stopped", vim.log.levels.INFO)
  end, { desc = "Stop Codex app-server" })

  vim.api.nvim_create_user_command("CodexStatus", function()
    if is_connected() then
      vim.notify(
        "codex: connected" .. (M.state.port and " on port " .. M.state.port or ""),
        vim.log.levels.INFO
      )
    else
      vim.notify("codex: not connected", vim.log.levels.WARN)
    end
  end, { desc = "Show Codex connection status" })
end

function M.setup(opts)
  local config = require("codex.config")
  local terminal = require("codex.terminal")

  M.state.config = config.apply(opts or {})
  config.validate(M.state.config)

  terminal.setup(M.state.config)
  create_commands()

  M.state.initialized = true

  if M.state.config.auto_start then
    start_server()
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `busted tests/unit/init_spec.lua`

Expected: All tests pass (setup, 12 command registrations, enqueue_mention).

- [ ] **Step 5: Run entire test suite to confirm no Phase 1 regressions**

Run:
```
busted tests/unit/
```

Expected: All tests pass — Phase 1 suite (61 tests) + Phase 2 suite.

- [ ] **Step 6: Commit**

```bash
git add lua/codex/init.lua tests/unit/init_spec.lua
git commit -m "feat(phase2): replace init.lua stub with full setup(), 12 commands, mention queue"
```

- [ ] **Step 7: Tag phase-2-complete**

```bash
git tag phase-2-complete
```

---

## Verification

After all tasks complete, verify Phase 2 manually:

```bash
# Headless load test — should print nothing and exit 0
nvim --headless -c "lua local ok, err = pcall(require, 'codex'); if not ok then print(err) end" -c "qa"

# Command registration smoke test
nvim --headless \
  -c "lua require('codex').setup({ auto_start = false })" \
  -c "lua local cmds = vim.api.nvim_get_commands({}); local missing = {}; for _, n in ipairs({'Codex','CodexStart','CodexStop','CodexStatus','CodexAdd','CodexClose','CodexOpen','CodexFocus'}) do if not cmds[n] then table.insert(missing, n) end end; if #missing > 0 then print('MISSING: ' .. table.concat(missing, ', ')); vim.cmd('cq') end; print('All commands registered')" \
  -c "qa"

# All unit tests
cd /home/eugene/Desktop/MyRepo/codex.nvim && busted tests/unit/
```
