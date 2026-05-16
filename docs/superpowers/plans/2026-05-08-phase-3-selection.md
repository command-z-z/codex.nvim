# Phase 3: Selection Tracking + Visual Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement real-time selection tracking (`selection.lua`), visual command handling (`visual_commands.lua`), and wire `CodexSend` + `selection.enable()` into `init.lua` — enabling `:CodexSend` to send the current file+range as an at-mention to codex.

**Architecture:** `selection.lua` uses `uv.new_timer` for 50ms debounce and 50ms visual-demotion timers, sending `$/codex/selectionChanged` RPC notifications when the selection changes. `visual_commands.lua` captures line range before exiting visual mode and delegates to `codex.init.enqueue_mention`. `init.lua` calls `selection.enable(rpc, ...)` after connection and wires `CodexSend` to `visual_commands.handle_send`.

**Tech Stack:** Pure Lua, `vim.uv`/`vim.loop` timers, `vim.api` autocmds, busted (Lua 5.1), existing Phase 1–2 modules (`codex.rpc`, `codex.terminal`, `codex.init`).

---

## File Map

| File | Role |
|------|------|
| `lua/codex/selection.lua` | Selection tracking: debounce, demotion timer, RPC notify on change |
| `lua/codex/visual_commands.lua` | Visual mode capture: ESC + schedule, `handle_send` |
| `lua/codex/init.lua` | Modified: real `CodexSend`, `selection.enable` on connect, `selection.disable` on stop |

**Vim mock gaps for Phase 3 tests** (stub in each spec's `before_each`):
- `vim.schedule_wrap` — not in mock; use `function(fn) return fn end`
- `vim.api.nvim_get_mode` — not in mock; default to `function() return { mode = "n" } end`
- `vim.api.nvim_replace_termcodes` — not in mock; return the input string
- `vim.api.nvim_feedkeys` — not in mock; record calls in a table
- `vim.fn.visualmode` — not in mock; default to `function() return "" end`
- `vim.deepcopy` — not in mock; use a shallow copy helper
- `vim.fn.getpos("v")` — mock returns `{0,0,0,0}`; override per-test when visual mode needed

---

## Task 1: selection.lua — complete selection tracking module

**Files:**
- Create: `lua/codex/selection.lua`
- Create: `tests/unit/selection_spec.lua`

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/selection_spec.lua
require("busted_setup")

describe("codex.selection", function()
  local selection

  before_each(function()
    package.loaded["codex.selection"] = nil
    package.loaded["codex.terminal"] = nil

    -- stub codex.terminal
    package.preload["codex.terminal"] = function()
      return { get_active_terminal_bufnr = function() return nil end }
    end

    -- stubs for vim APIs not in mock
    _G.vim.schedule_wrap = function(fn) return fn end
    _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
    _G.vim.fn.visualmode = function() return "" end
    _G.vim.deepcopy = function(t)
      local c = {}
      for k, v in pairs(t) do c[k] = v end
      return c
    end

    selection = require("codex.selection")
  end)

  after_each(function()
    package.preload["codex.terminal"] = nil
    if selection.state.tracking_enabled then
      selection.disable()
    end
  end)

  -- ── has_selection_changed ──────────────────────────────────────────
  describe("has_selection_changed()", function()
    local function make_sel(file, text, sl, sc, el, ec)
      return {
        filePath = file,
        text = text,
        selection = {
          start = { line = sl, character = sc },
          ["end"] = { line = el, character = ec },
          isEmpty = (text == ""),
        },
      }
    end

    it("returns true when latest_selection is nil", function()
      selection.state.latest_selection = nil
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","",0,0,0,0)))
    end)

    it("returns false when selection is identical", function()
      local s = make_sel("/a.lua","hi",0,0,0,2)
      selection.state.latest_selection = s
      assert.is_false(selection.has_selection_changed(s))
    end)

    it("returns true when filePath differs", function()
      selection.state.latest_selection = make_sel("/a.lua","",0,0,0,0)
      assert.is_true(selection.has_selection_changed(make_sel("/b.lua","",0,0,0,0)))
    end)

    it("returns true when text differs", function()
      selection.state.latest_selection = make_sel("/a.lua","old",0,0,0,3)
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","new",0,0,0,3)))
    end)

    it("returns true when start.line differs", function()
      selection.state.latest_selection = make_sel("/a.lua","",0,0,0,0)
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","",1,0,1,0)))
    end)

    it("returns true when end.character differs", function()
      selection.state.latest_selection = make_sel("/a.lua","hi",0,0,0,2)
      assert.is_true(selection.has_selection_changed(make_sel("/a.lua","hi",0,0,0,5)))
    end)
  end)

  -- ── get_cursor_position ───────────────────────────────────────────
  describe("get_cursor_position()", function()
    before_each(function()
      _G.vim.api.nvim_win_get_cursor = function() return { 5, 3 } end
      _G.vim.api.nvim_buf_get_name = function() return "/path/to/file.lua" end
    end)

    it("returns isEmpty = true", function()
      assert.is_true(selection.get_cursor_position().selection.isEmpty)
    end)

    it("converts 1-indexed row to 0-indexed line", function()
      local pos = selection.get_cursor_position()
      assert.equals(4, pos.selection.start.line)  -- row 5 → line 4
    end)

    it("passes column through unchanged", function()
      local pos = selection.get_cursor_position()
      assert.equals(3, pos.selection.start.character)
    end)

    it("sets fileUrl with file:// prefix", function()
      local pos = selection.get_cursor_position()
      assert.equals("file:///path/to/file.lua", pos.fileUrl)
    end)

    it("start and end are the same point", function()
      local pos = selection.get_cursor_position()
      assert.same(pos.selection.start, pos.selection["end"])
    end)
  end)

  -- ── get_range_selection ──────────────────────────────────────────
  describe("get_range_selection()", function()
    before_each(function()
      _G.vim.api.nvim_buf_get_name = function() return "/test.lua" end
      _G.vim.api.nvim_buf_line_count = function() return 100 end
      _G.vim.api.nvim_buf_get_lines = function(_, s, e, _)
        local lines = {}
        for i = s + 1, e do
          table.insert(lines, "line_" .. i)
        end
        return lines
      end
    end)

    it("returns nil when line1 > line2", function()
      assert.is_nil(selection.get_range_selection(5, 3))
    end)

    it("returns nil when line1 < 1", function()
      assert.is_nil(selection.get_range_selection(0, 5))
    end)

    it("returns 0-indexed start line", function()
      local sel = selection.get_range_selection(3, 5)
      assert.equals(2, sel.selection.start.line)  -- 3-1
    end)

    it("returns 0-indexed end line", function()
      local sel = selection.get_range_selection(3, 5)
      assert.equals(4, sel.selection["end"].line)  -- 5-1
    end)

    it("sets filePath and fileUrl", function()
      local sel = selection.get_range_selection(1, 2)
      assert.equals("/test.lua", sel.filePath)
      assert.equals("file:///test.lua", sel.fileUrl)
    end)

    it("isEmpty = false for non-empty range", function()
      local sel = selection.get_range_selection(1, 3)
      assert.is_false(sel.selection.isEmpty)
    end)

    it("handles single-line range", function()
      local sel = selection.get_range_selection(4, 4)
      assert.equals(3, sel.selection.start.line)
      assert.equals(3, sel.selection["end"].line)
    end)
  end)

  -- ── enable / disable ────────────────────────────────────────────
  describe("enable() / disable()", function()
    local fake_rpc

    before_each(function()
      fake_rpc = { notify = function() end }
    end)

    it("sets tracking_enabled = true", function()
      selection.enable(fake_rpc, 50)
      assert.is_true(selection.state.tracking_enabled)
    end)

    it("stores rpc reference", function()
      selection.enable(fake_rpc, 50)
      assert.equals(fake_rpc, selection.rpc)
    end)

    it("is idempotent — second enable is a no-op", function()
      selection.enable(fake_rpc, 50)
      local rpc2 = { notify = function() end }
      selection.enable(rpc2, 50)
      assert.equals(fake_rpc, selection.rpc)  -- first rpc unchanged
    end)

    it("sets tracking_enabled = false after disable", function()
      selection.enable(fake_rpc, 50)
      selection.disable()
      assert.is_false(selection.state.tracking_enabled)
    end)

    it("clears rpc after disable", function()
      selection.enable(fake_rpc, 50)
      selection.disable()
      assert.is_nil(selection.rpc)
    end)

    it("clears latest_selection after disable", function()
      selection.enable(fake_rpc, 50)
      selection.state.latest_selection = { filePath = "/a.lua" }
      selection.disable()
      assert.is_nil(selection.state.latest_selection)
    end)
  end)

  -- ── send_selection_update ────────────────────────────────────────
  describe("send_selection_update()", function()
    it("calls rpc:notify with correct method and payload", function()
      local calls = {}
      selection.rpc = {
        notify = function(self, method, params)
          table.insert(calls, { method = method, params = params })
        end,
      }
      local sel = { filePath = "/a.lua", text = "hi",
        selection = { start={line=0,character=0}, ["end"]={line=0,character=2}, isEmpty=false } }
      selection.send_selection_update(sel)
      assert.equals(1, #calls)
      assert.equals("$/codex/selectionChanged", calls[1].method)
      assert.equals(sel, calls[1].params)
    end)

    it("is safe when rpc is nil", function()
      selection.rpc = nil
      assert.has_no.errors(function()
        selection.send_selection_update({ filePath = "/a.lua" })
      end)
    end)
  end)

  -- ── debounce_update ──────────────────────────────────────────────
  describe("debounce_update()", function()
    it("calls update_selection after timer fires", function()
      local update_called = false
      local original_update = selection.update_selection
      selection.update_selection = function() update_called = true end

      -- Override timer to fire callback immediately
      local orig_timer = _G.vim.loop.new_timer
      _G.vim.loop.new_timer = function()
        return {
          start = function(self, _, _, cb) cb() end,
          stop  = function(self) end,
          close = function(self) end,
        }
      end
      _G.vim.uv.new_timer = _G.vim.loop.new_timer

      selection.state.tracking_enabled = true
      selection.debounce_update()

      selection.update_selection = original_update
      _G.vim.loop.new_timer = orig_timer
      _G.vim.uv.new_timer = orig_timer

      assert.is_true(update_called)
    end)

    it("cancels a pending timer before creating a new one", function()
      local stop_count = 0
      local orig_timer = _G.vim.loop.new_timer
      _G.vim.loop.new_timer = function()
        return {
          start = function(self, _, _, cb) end,  -- do NOT fire
          stop  = function(self) stop_count = stop_count + 1 end,
          close = function(self) end,
        }
      end
      _G.vim.uv.new_timer = _G.vim.loop.new_timer

      -- First call — installs a timer
      selection.debounce_update()
      -- Second call — should cancel the first timer then create another
      selection.debounce_update()

      _G.vim.loop.new_timer = orig_timer
      _G.vim.uv.new_timer = orig_timer

      assert.is_true(stop_count >= 1, "first timer should have been stopped")
    end)
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

```
cd /home/eugene/Desktop/MyRepo/codex.nvim && make test-unit 2>&1 | grep "selection_spec"
```

Expected: errors about missing module `codex.selection`

- [ ] **Step 3: Implement selection.lua**

```lua
-- lua/codex/selection.lua
local M = {}

local uv = vim.uv or vim.loop
local terminal = require("codex.terminal")

M.state = {
  latest_selection = nil,
  tracking_enabled = false,
  debounce_timer = nil,
  debounce_ms = 50,
  last_active_visual_selection = nil,
  demotion_timer = nil,
  visual_demotion_delay_ms = 50,
}

function M.enable(rpc, visual_demotion_delay_ms)
  if M.state.tracking_enabled then return end
  M.state.tracking_enabled = true
  M.rpc = rpc
  M.state.visual_demotion_delay_ms = visual_demotion_delay_ms or 50
  M._create_autocommands()
end

function M.disable()
  if not M.state.tracking_enabled then return end
  M.state.tracking_enabled = false
  M._clear_autocommands()
  M.state.latest_selection = nil
  M.state.last_active_visual_selection = nil
  M.rpc = nil
  M._cancel_debounce_timer()
  M._cancel_demotion_timer()
end

function M._cancel_debounce_timer()
  local timer = M.state.debounce_timer
  if not timer then return end
  M.state.debounce_timer = nil
  timer:stop()
  timer:close()
end

function M._cancel_demotion_timer()
  local timer = M.state.demotion_timer
  if not timer then return end
  M.state.demotion_timer = nil
  timer:stop()
  timer:close()
end

function M._create_autocommands()
  local group = vim.api.nvim_create_augroup("CodexSelection", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
    group = group,
    callback = function() M.on_cursor_moved() end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function() M.on_mode_changed() end,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = function() M.on_text_changed() end,
  })
end

function M._clear_autocommands()
  vim.api.nvim_clear_autocmds({ group = "CodexSelection" })
end

function M.on_cursor_moved()  M.debounce_update() end
function M.on_mode_changed()  M.debounce_update() end
function M.on_text_changed()  M.debounce_update() end

function M.debounce_update()
  M._cancel_debounce_timer()
  local timer = uv.new_timer()
  M.state.debounce_timer = timer
  timer:start(M.state.debounce_ms, 0, vim.schedule_wrap(function()
    if M.state.debounce_timer ~= timer then return end
    M.state.debounce_timer = nil
    timer:stop()
    timer:close()
    M.update_selection()
  end))
end

function M.update_selection()
  if not M.state.tracking_enabled then return end

  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)

  if buf_name and buf_name:match("^term://") and buf_name:lower():find("codex", 1, true) then
    M._cancel_demotion_timer()
    return
  end

  local codex_term_bufnr = terminal.get_active_terminal_bufnr()
  if codex_term_bufnr and current_buf == codex_term_bufnr then
    M._cancel_demotion_timer()
    return
  end

  local current_mode = vim.api.nvim_get_mode().mode
  local current_selection

  if current_mode == "v" or current_mode == "V" or current_mode == "\022" then
    M._cancel_demotion_timer()
    current_selection = M.get_visual_selection()
    if current_selection then
      M.state.last_active_visual_selection = {
        bufnr = current_buf,
        selection_data = vim.deepcopy(current_selection),
        timestamp = vim.loop.now(),
      }
    else
      if M.state.last_active_visual_selection
        and M.state.last_active_visual_selection.bufnr == current_buf then
        M.state.last_active_visual_selection = nil
      end
    end
  else
    local last_visual = M.state.last_active_visual_selection

    if M.state.demotion_timer then
      current_selection = M.get_cursor_position()
    elseif last_visual and last_visual.bufnr == current_buf
      and last_visual.selection_data
      and not last_visual.selection_data.selection.isEmpty then
      current_selection = M.state.latest_selection
      local timer = uv.new_timer()
      M.state.demotion_timer = timer
      timer:start(M.state.visual_demotion_delay_ms, 0, vim.schedule_wrap(function()
        if M.state.demotion_timer ~= timer then return end
        M.state.demotion_timer = nil
        timer:stop()
        timer:close()
        M.handle_selection_demotion(current_buf)
      end))
    else
      current_selection = M.get_cursor_position()
      if last_visual and last_visual.bufnr == current_buf then
        M.state.last_active_visual_selection = nil
      end
    end
  end

  if not current_selection then
    current_selection = M.get_cursor_position()
  end

  if M.has_selection_changed(current_selection) then
    M.state.latest_selection = current_selection
    if M.rpc then
      M.send_selection_update(current_selection)
    end
  end
end

function M.handle_selection_demotion(original_bufnr)
  if not M.state.tracking_enabled then return end

  local current_buf = vim.api.nvim_get_current_buf()
  local codex_term_bufnr = terminal.get_active_terminal_bufnr()

  if codex_term_bufnr and current_buf == codex_term_bufnr then
    if M.state.last_active_visual_selection
      and M.state.last_active_visual_selection.bufnr == original_bufnr then
      M.state.last_active_visual_selection = nil
    end
    return
  end

  local mode = vim.api.nvim_get_mode().mode
  if current_buf == original_bufnr
    and (mode == "v" or mode == "V" or mode == "\022") then
    if M.state.last_active_visual_selection
      and M.state.last_active_visual_selection.bufnr == original_bufnr then
      M.state.last_active_visual_selection = nil
    end
    return
  end

  if current_buf == original_bufnr then
    local new_sel = M.get_cursor_position()
    if M.has_selection_changed(new_sel) then
      M.state.latest_selection = new_sel
      if M.rpc then M.send_selection_update(M.state.latest_selection) end
    end
  end

  if M.state.last_active_visual_selection
    and M.state.last_active_visual_selection.bufnr == original_bufnr then
    M.state.last_active_visual_selection = nil
  end
end

-- ── Pure helper functions ─────────────────────────────────────────

local function validate_visual_mode()
  local mode = vim.api.nvim_get_mode().mode
  if not (mode == "v" or mode == "V" or mode == "\022") then
    return false, "not in visual mode"
  end
  local anchor = vim.fn.getpos("v")
  if anchor[2] == 0 then return false, "no visual selection mark" end
  return true, nil
end

local function get_effective_visual_mode()
  local vm = (vim.fn.visualmode and vim.fn.visualmode()) or ""
  if vm ~= "" then return vm end
  local mode = vim.api.nvim_get_mode().mode
  if mode == "V" then return "V"
  elseif mode == "v" then return "v"
  elseif mode == "\022" then return "\022"
  end
  return nil
end

local function get_selection_coordinates()
  local anchor = vim.fn.getpos("v")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local p1 = { lnum = anchor[2], col = anchor[3] }
  local p2 = { lnum = cursor[1], col = cursor[2] + 1 }
  if p1.lnum < p2.lnum or (p1.lnum == p2.lnum and p1.col <= p2.col) then
    return p1, p2
  else
    return p2, p1
  end
end

local function extract_linewise_text(lines, start_coords)
  start_coords.col = 1
  return table.concat(lines, "\n")
end

local function extract_characterwise_text(lines, sc, ec)
  if sc.lnum == ec.lnum then
    if not lines[1] then return nil end
    return string.sub(lines[1], sc.col, ec.col)
  else
    if not lines[1] or not lines[#lines] then return nil end
    local parts = { string.sub(lines[1], sc.col) }
    for i = 2, #lines - 1 do table.insert(parts, lines[i]) end
    table.insert(parts, string.sub(lines[#lines], 1, ec.col))
    return table.concat(parts, "\n")
  end
end

local function calculate_lsp_positions(sc, ec, visual_mode, lines)
  local s_char, e_char
  if visual_mode == "V" then
    s_char = 0
    e_char = (#lines > 0 and lines[#lines]) and #lines[#lines] or 0
  else
    s_char = sc.col - 1
    e_char = ec.col
  end
  return {
    start = { line = sc.lnum - 1, character = s_char },
    ["end"] = { line = ec.lnum - 1, character = e_char },
  }
end

function M.get_visual_selection()
  local valid = validate_visual_mode()
  if not valid then return nil end
  local vm = get_effective_visual_mode()
  if not vm then return nil end
  local sc, ec = get_selection_coordinates()
  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)
  local lines = vim.api.nvim_buf_get_lines(current_buf, sc.lnum - 1, ec.lnum, false)
  if #lines == 0 then return nil end

  local text
  if vm == "V" then
    text = extract_linewise_text(lines, sc)
  elseif vm == "v" or vm == "\022" then
    text = extract_characterwise_text(lines, sc, ec)
    if not text then return nil end
  else
    return nil
  end

  local lsp = calculate_lsp_positions(sc, ec, vm, lines)
  return {
    text = text or "",
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = lsp.start,
      ["end"] = lsp["end"],
      isEmpty = (not text or #text == 0),
    },
  }
end

function M.get_cursor_position()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)
  return {
    text = "",
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = cursor[1] - 1, character = cursor[2] },
      ["end"] = { line = cursor[1] - 1, character = cursor[2] },
      isEmpty = true,
    },
  }
end

function M.has_selection_changed(new_sel)
  local old = M.state.latest_selection
  if not new_sel then return old ~= nil end
  if not old then return true end
  if old.filePath ~= new_sel.filePath then return true end
  if old.text ~= new_sel.text then return true end
  if old.selection.start.line ~= new_sel.selection.start.line
    or old.selection.start.character ~= new_sel.selection.start.character
    or old.selection["end"].line ~= new_sel.selection["end"].line
    or old.selection["end"].character ~= new_sel.selection["end"].character then
    return true
  end
  return false
end

function M.send_selection_update(selection)
  if M.rpc then
    M.rpc:notify("$/codex/selectionChanged", selection)
  end
end

function M.get_latest_selection()
  return M.state.latest_selection
end

function M.get_range_selection(line1, line2)
  if not line1 or not line2 or line1 < 1 or line2 < 1 or line1 > line2 then
    return nil
  end
  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)
  local total = vim.api.nvim_buf_line_count(current_buf)
  if line2 > total then line2 = total end
  local lines = vim.api.nvim_buf_get_lines(current_buf, line1 - 1, line2, false)
  if #lines == 0 then return nil end
  local text = table.concat(lines, "\n")
  return {
    text = text or "",
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = line1 - 1, character = 0 },
      ["end"] = { line = line2 - 1, character = #lines[#lines] },
      isEmpty = (not text or #text == 0),
    },
  }
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```
make test-unit 2>&1 | tail -5
```

Expected: all tests pass (count will be 173 + new selection tests).

- [ ] **Step 5: Commit**

```bash
git add lua/codex/selection.lua tests/unit/selection_spec.lua
git commit -m "feat(phase3): add selection.lua — debounced selection tracking + RPC notify"
```

---

## Task 2: visual_commands.lua — visual mode command handling

**Files:**
- Create: `lua/codex/visual_commands.lua`
- Create: `tests/unit/visual_commands_spec.lua`

The module is simpler than `claudecode.nvim/visual_commands.lua` — no tree-buffer handling needed (YAGNI). Core: capture visual range before ESC, schedule callback, and `handle_send` builds a file-path mention.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/unit/visual_commands_spec.lua
require("busted_setup")

describe("codex.visual_commands", function()
  local vc
  local mention_calls, feedkeys_calls

  before_each(function()
    package.loaded["codex.visual_commands"] = nil
    package.loaded["codex.init"] = nil

    mention_calls = {}
    feedkeys_calls = {}

    _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
    _G.vim.api.nvim_replace_termcodes = function(s, _, _, _) return s end
    _G.vim.api.nvim_feedkeys = function(keys, _, _)
      table.insert(feedkeys_calls, keys)
    end
    _G.vim.fn.getpos = function(mark)
      if mark == "v"  then return { 0, 0, 0, 0 } end
      if mark == "'<" then return { 0, 1, 1, 0 } end
      if mark == "'>" then return { 0, 1, 10, 0 } end
      return { 0, 0, 0, 0 }
    end

    package.preload["codex.init"] = function()
      return {
        enqueue_mention = function(text)
          table.insert(mention_calls, text)
        end,
      }
    end

    vc = require("codex.visual_commands")
  end)

  after_each(function()
    package.preload["codex.init"] = nil
  end)

  -- ── validate_visual_mode ─────────────────────────────────────────
  describe("validate_visual_mode()", function()
    it("returns false in normal mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      local ok, err = vc.validate_visual_mode()
      assert.is_false(ok)
      assert.is_truthy(err:find("Not in visual mode"))
    end)

    it("returns true in 'v' mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      assert.is_true(vc.validate_visual_mode())
    end)

    it("returns true in 'V' (linewise) mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "V" } end
      assert.is_true(vc.validate_visual_mode())
    end)
  end)

  -- ── get_visual_range ─────────────────────────────────────────────
  describe("get_visual_range()", function()
    it("uses cursor + anchor in visual mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 10, 0 } end
      _G.vim.fn.getpos = function(m)
        if m == "v" then return { 0, 5, 1, 0 } end
        return { 0, 0, 0, 0 }
      end
      local s, e = vc.get_visual_range()
      assert.equals(5, s)
      assert.equals(10, e)
    end)

    it("uses '<,'> marks when not in visual mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      _G.vim.fn.getpos = function(m)
        if m == "'<" then return { 0, 3, 1, 0 } end
        if m == "'>" then return { 0, 8, 1, 0 } end
        return { 0, 0, 0, 0 }
      end
      local s, e = vc.get_visual_range()
      assert.equals(3, s)
      assert.equals(8, e)
    end)

    it("returns at least 1 for both values even with zero marks", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      _G.vim.fn.getpos = function() return { 0, 0, 0, 0 } end
      local s, e = vc.get_visual_range()
      assert.is_true(s >= 1)
      assert.is_true(e >= 1)
    end)

    it("swaps start/end if reversed", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
      _G.vim.fn.getpos = function(m)
        if m == "v" then return { 0, 10, 1, 0 } end
        return { 0, 0, 0, 0 }
      end
      local s, e = vc.get_visual_range()
      assert.equals(3, s)
      assert.equals(10, e)
    end)
  end)

  -- ── handle_send ──────────────────────────────────────────────────
  describe("handle_send()", function()
    before_each(function()
      _G.vim.api.nvim_get_current_buf = function() return 1 end
      _G.vim.api.nvim_buf_get_name = function() return "/project/main.lua" end
    end)

    it("enqueues file:start-end mention for a valid range", function()
      vc.handle_send(5, 10)
      assert.equals(1, #mention_calls)
      assert.equals("/project/main.lua:5-10", mention_calls[1])
    end)

    it("enqueues just the file path when no range given", function()
      vc.handle_send(nil, nil)
      assert.equals(1, #mention_calls)
      assert.equals("/project/main.lua", mention_calls[1])
    end)

    it("enqueues single line as start-end with same line", function()
      vc.handle_send(7, 7)
      assert.equals("/project/main.lua:7-7", mention_calls[1])
    end)

    it("warns and does not enqueue when buffer has no file", function()
      _G.vim.api.nvim_buf_get_name = function() return "" end
      local warned = false
      local orig_notify = _G.vim.notify
      _G.vim.notify = function(_, lvl) if lvl == vim.log.levels.WARN then warned = true end end
      vc.handle_send(1, 5)
      _G.vim.notify = orig_notify
      assert.is_true(warned)
      assert.equals(0, #mention_calls)
    end)
  end)

  -- ── exit_visual_and_schedule ─────────────────────────────────────
  describe("exit_visual_and_schedule()", function()
    it("sends ESC key", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
      _G.vim.fn.getpos = function(m) if m == "v" then return {0,3,0,0} end; return {0,0,0,0} end
      vc.exit_visual_and_schedule(function() end)
      assert.equals(1, #feedkeys_calls)
    end)

    it("calls callback with start and end line", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 8, 0 } end
      _G.vim.fn.getpos = function(m) if m == "v" then return {0,4,0,0} end; return {0,0,0,0} end

      local cb_args = nil
      vc.exit_visual_and_schedule(function(s, e) cb_args = { s, e } end)
      assert.is_not_nil(cb_args)
      assert.equals(4, cb_args[1])  -- start
      assert.equals(8, cb_args[2])  -- end
    end)
  end)

  -- ── create_visual_command_wrapper ────────────────────────────────
  describe("create_visual_command_wrapper()", function()
    it("calls normal_handler in normal mode", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "n" } end
      local normal_called = false
      local fn = vc.create_visual_command_wrapper(
        function() normal_called = true end,
        function() end
      )
      fn()
      assert.is_true(normal_called)
    end)

    it("calls visual_handler in visual mode (via exit_visual_and_schedule)", function()
      _G.vim.api.nvim_get_mode = function() return { mode = "v" } end
      _G.vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
      _G.vim.fn.getpos = function(m) if m == "v" then return {0,1,0,0} end; return {0,0,0,0} end

      local visual_called = false
      local fn = vc.create_visual_command_wrapper(
        function() end,
        function() visual_called = true end
      )
      fn()
      assert.is_true(visual_called)
    end)
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

```
make test-unit 2>&1 | grep "visual_commands_spec"
```

Expected: errors about missing module `codex.visual_commands`

- [ ] **Step 3: Implement visual_commands.lua**

```lua
-- lua/codex/visual_commands.lua
local M = {}

local ESC_KEY
local ok = pcall(function()
  ESC_KEY = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
end)
if not ok then
  ESC_KEY = "\27"
end

local function get_current_mode()
  local mode = "n"
  pcall(function()
    if vim.api and vim.api.nvim_get_mode then
      mode = vim.api.nvim_get_mode().mode
    else
      mode = vim.fn.mode(true)
    end
  end)
  return mode
end

function M.validate_visual_mode()
  local mode = get_current_mode()
  local is_visual = mode == "v" or mode == "V" or mode == "\022"
  if not is_visual then
    return false, "Not in visual mode (current mode: " .. mode .. ")"
  end
  return true, nil
end

function M.get_visual_range()
  local start_pos, end_pos = 1, 1
  pcall(function()
    local mode = get_current_mode()
    local is_visual = mode == "v" or mode == "V" or mode == "\022"
    if is_visual then
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      local anchor = vim.fn.getpos("v")[2]
      if anchor > 0 then
        start_pos = math.min(cursor, anchor)
        end_pos   = math.max(cursor, anchor)
      else
        start_pos = cursor
        end_pos   = cursor
      end
    else
      local mark_s = vim.fn.getpos("'<")[2]
      local mark_e = vim.fn.getpos("'>")[2]
      if mark_s > 0 and mark_e > 0 then
        start_pos = mark_s
        end_pos   = mark_e
      else
        local cursor = vim.api.nvim_win_get_cursor(0)[1]
        start_pos = cursor
        end_pos   = cursor
      end
    end
  end)
  if end_pos < start_pos then start_pos, end_pos = end_pos, start_pos end
  start_pos = math.max(1, start_pos)
  end_pos   = math.max(1, end_pos)
  return start_pos, end_pos
end

function M.exit_visual_and_schedule(callback, ...)
  local args = { ... }
  local start_line, end_line = M.get_visual_range()

  pcall(function()
    vim.api.nvim_feedkeys(ESC_KEY, "i", true)
  end)

  local sched = vim.schedule or function(fn) fn() end
  sched(function()
    callback(start_line, end_line, unpack(args))
  end)
end

function M.create_visual_command_wrapper(normal_handler, visual_handler)
  return function(...)
    local mode = get_current_mode()
    if mode == "v" or mode == "V" or mode == "\022" then
      M.exit_visual_and_schedule(visual_handler, ...)
    else
      normal_handler(...)
    end
  end
end

---Handle CodexSend: build file:start-end mention and enqueue.
---@param line1 number|nil 1-indexed start line (provided by `:range` command or nil)
---@param line2 number|nil 1-indexed end line
function M.handle_send(line1, line2)
  local file_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if file_path == "" then
    vim.notify("CodexSend: buffer has no file path", vim.log.levels.WARN)
    return
  end

  local mention
  if line1 and line2 and line1 > 0 and line2 >= line1 then
    mention = file_path .. ":" .. line1 .. "-" .. line2
  else
    mention = file_path
  end

  require("codex.init").enqueue_mention(mention)
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```
make test-unit 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/visual_commands.lua tests/unit/visual_commands_spec.lua
git commit -m "feat(phase3): add visual_commands.lua — visual range capture + CodexSend handler"
```

---

## Task 3: init.lua — wire CodexSend + selection.enable on connect

**Files:**
- Modify: `lua/codex/init.lua`
- Modify: `tests/unit/init_spec.lua`

Three changes to `init.lua`:

1. **`CodexSend` command** — replace the stub notification with `visual_commands.handle_send(args.line1, args.line2)`.
2. **`on_connected()`** — after setting `M.state.rpc`, call `selection.enable(rpc, config.visual_demotion_delay_ms)` when `track_selection` is true.
3. **`CodexStop` command** — call `selection.disable()` before stopping.

- [ ] **Step 1: Read the current init.lua**

Read `lua/codex/init.lua` to find the exact lines for each change before editing.

- [ ] **Step 2: Apply change 1 — real CodexSend**

Find the `CodexSend` command registration:

```lua
-- CURRENT (stub):
vim.api.nvim_create_user_command("CodexSend", function()
  vim.notify("CodexSend: implemented in Phase 3", vim.log.levels.INFO)
end, { range = true, desc = "Send selection to Codex" })
```

Replace with:

```lua
-- NEW:
vim.api.nvim_create_user_command("CodexSend", function(args)
  local visual_commands = require("codex.visual_commands")
  visual_commands.handle_send(args.line1, args.line2)
end, { range = true, desc = "Send selection to Codex" })
```

- [ ] **Step 3: Apply change 2 — selection.enable on connect**

Find `on_connected()`:

```lua
-- CURRENT:
local function on_connected(rpc)
  M.state.rpc = rpc
  if #M.state.mention_queue > 0 then
    schedule_flush()
  end
end
```

Replace with:

```lua
-- NEW:
local function on_connected(rpc)
  M.state.rpc = rpc
  if M.state.config and M.state.config.track_selection then
    local selection = require("codex.selection")
    selection.enable(rpc, M.state.config.visual_demotion_delay_ms)
  end
  if #M.state.mention_queue > 0 then
    schedule_flush()
  end
end
```

- [ ] **Step 4: Apply change 3 — selection.disable in CodexStop**

Find the `CodexStop` command registration:

```lua
-- CURRENT:
vim.api.nvim_create_user_command("CodexStop", function()
  if M.state.rpc then
    M.state.rpc:close()
    M.state.rpc = nil
  end
  require("codex.app_server").stop()
  vim.notify("codex: stopped", vim.log.levels.INFO)
end, { desc = "Stop Codex app-server" })
```

Replace with:

```lua
-- NEW:
vim.api.nvim_create_user_command("CodexStop", function()
  local selection = require("codex.selection")
  selection.disable()
  if M.state.rpc then
    M.state.rpc:close()
    M.state.rpc = nil
  end
  require("codex.app_server").stop()
  vim.notify("codex: stopped", vim.log.levels.INFO)
end, { desc = "Stop Codex app-server" })
```

- [ ] **Step 5: Add tests to init_spec.lua**

Add these tests after the existing `describe("command registration")` block:

```lua
describe("CodexSend command", function()
  local vc_calls

  before_each(function()
    vc_calls = {}
    package.preload["codex.visual_commands"] = function()
      return {
        handle_send = function(l1, l2)
          table.insert(vc_calls, { line1 = l1, line2 = l2 })
        end,
      }
    end
    codex.setup({})
  end)

  after_each(function()
    package.preload["codex.visual_commands"] = nil
    package.loaded["codex.visual_commands"] = nil
  end)

  it("calls visual_commands.handle_send with line1 and line2", function()
    local codex_send = registered_cmds["CodexSend"]
    assert.is_not_nil(codex_send)
    codex_send.cb({ line1 = 3, line2 = 7 })
    assert.equals(1, #vc_calls)
    assert.equals(3, vc_calls[1].line1)
    assert.equals(7, vc_calls[1].line2)
  end)
end)

describe("CodexStop command", function()
  local selection_disabled

  before_each(function()
    selection_disabled = false
    package.preload["codex.selection"] = function()
      return {
        enable = function() end,
        disable = function() selection_disabled = true end,
      }
    end
    codex.setup({})
  end)

  after_each(function()
    package.preload["codex.selection"] = nil
    package.loaded["codex.selection"] = nil
  end)

  it("calls selection.disable() on stop", function()
    local stop_cmd = registered_cmds["CodexStop"]
    assert.is_not_nil(stop_cmd)
    stop_cmd.cb({})
    assert.is_true(selection_disabled)
  end)
end)
```

- [ ] **Step 6: Run all tests**

```
make test-unit 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lua/codex/init.lua tests/unit/init_spec.lua
git commit -m "feat(phase3): wire CodexSend to visual_commands, enable selection tracking on connect"
```

- [ ] **Step 8: Tag phase-3-complete**

```bash
git tag phase-3-complete
```

---

## Verification

```bash
# All tests pass
make test-unit

# Headless load test
nvim --headless \
  -c "lua require('codex').setup({ auto_start = false, track_selection = false })" \
  -c "lua print('Phase 3 loaded OK')" \
  -c "qa"
```
