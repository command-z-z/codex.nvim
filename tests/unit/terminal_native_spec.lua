require("busted_setup")

describe("codex.terminal.native", function()
  local native

  -- Track calls to stubs
  local termopen_calls
  local jobstop_calls
  local cmd_calls
  local win_set_height_calls

  before_each(function()
    -- Reset the vim mock state
    _G.vim._mock.reset()
    _G.vim._mock.add_buffer(1, "/home/user/project/test.lua", "local test = {}\nreturn test")
    _G.vim._mock.add_window(1000, 1, { 1, 0 })
    _G.vim._win_tab[1000] = 1
    _G.vim._tab_windows[1] = { 1000 }
    _G.vim._current_window = 1000

    -- Reset call trackers
    termopen_calls = {}
    jobstop_calls = {}
    cmd_calls = {}
    win_set_height_calls = {}

    -- Stub vim.fn.termopen — returns a valid job id (1)
    _G.vim.fn.termopen = function(cmd_arg, opts)
      table.insert(termopen_calls, { cmd = cmd_arg, opts = opts })
      -- Simulate that nvim_get_current_buf returns a new buffer after enew
      -- The mock's cmd("enew") doesn't exist yet, so termopen just returns job id
      return 1
    end

    -- Stub vim.fn.jobstop
    _G.vim.fn.jobstop = function(id)
      table.insert(jobstop_calls, id)
      return 1
    end

    -- Extend vim.cmd to track calls and handle "enew" + "startinsert"
    local original_cmd = _G.vim.cmd
    _G.vim.cmd = function(command)
      table.insert(cmd_calls, command)
      if command == "enew" then
        -- Create a new buffer and set it as the current window's buffer
        local new_buf = _G.vim.api.nvim_create_buf(false, false)
        _G.vim.api.nvim_win_set_buf(_G.vim._current_window, new_buf)
      elseif command == "startinsert" then
        -- no-op
      else
        original_cmd(command)
      end
    end

    -- Stub nvim_win_set_height (not in mock)
    _G.vim.api.nvim_win_set_height = function(winid, height)
      table.insert(win_set_height_calls, { winid = winid, height = height })
    end

    -- Stub vim.bo (not in mock) — simple per-buffer options table
    _G.vim.bo = setmetatable({}, {
      __index = function(_, buf)
        if not _G.vim._buffers[buf] then
          return {}
        end
        if not _G.vim._buffers[buf].options then
          _G.vim._buffers[buf].options = {}
        end
        return _G.vim._buffers[buf].options
      end,
      __newindex = function(_, buf, tbl)
        if _G.vim._buffers[buf] then
          _G.vim._buffers[buf].options = tbl
        end
      end,
    })

    -- Stub vim.split to handle the 3-argument form used in native.lua
    _G.vim.split = function(str, sep, opts)
      local result = {}
      local plain = opts and opts.plain
      if plain then
        -- Plain string split
        local pattern = sep:gsub("([^%w])", "%%%1")
        local s = 1
        while true do
          local i, j = str:find(sep, s, true)
          if not i then
            table.insert(result, str:sub(s))
            break
          end
          table.insert(result, str:sub(s, i - 1))
          s = j + 1
        end
      else
        for part in str:gmatch("[^" .. sep .. "]+") do
          table.insert(result, part)
        end
      end
      return result
    end

    -- Fresh module load each test
    package.loaded["codex.terminal.native"] = nil
    package.loaded["codex.utils"] = nil
    native = require("codex.terminal.native")
  end)

  -- -----------------------------------------------------------------------
  -- is_available()
  -- -----------------------------------------------------------------------
  describe("is_available()", function()
    it("always returns true", function()
      assert.is_true(native.is_available())
    end)
  end)

  -- -----------------------------------------------------------------------
  -- get_active_bufnr() — before open
  -- -----------------------------------------------------------------------
  describe("get_active_bufnr()", function()
    it("returns nil before open()", function()
      assert.is_nil(native.get_active_bufnr())
    end)
  end)

  -- -----------------------------------------------------------------------
  -- open()
  -- -----------------------------------------------------------------------
  describe("open()", function()
    it("starts a terminal job (termopen called once)", function()
      native.open("codex", {})
      assert.are.equal(1, #termopen_calls)
    end)

    it("passes a table as the command argument to termopen", function()
      native.open("codex", {})
      assert.is_table(termopen_calls[1].cmd)
    end)

    it("splits a command with spaces into a table", function()
      native.open("codex --arg value", {})
      local cmd = termopen_calls[1].cmd
      assert.is_table(cmd)
      assert.are.equal("codex", cmd[1])
      assert.are.equal("--arg", cmd[2])
      assert.are.equal("value", cmd[3])
    end)

    it("wraps single-word command in a table", function()
      native.open("codex", {})
      local cmd = termopen_calls[1].cmd
      assert.is_table(cmd)
      assert.are.equal("codex", cmd[1])
    end)

    it("get_active_bufnr() returns a valid bufnr after open()", function()
      native.open("codex", {})
      local b = native.get_active_bufnr()
      assert.is_not_nil(b)
      assert.is_true(vim.api.nvim_buf_is_valid(b))
    end)

    it("is a no-op when terminal already open (termopen not called twice)", function()
      native.open("codex", {})
      assert.are.equal(1, #termopen_calls)

      native.open("codex", {})
      assert.are.equal(1, #termopen_calls) -- still 1
    end)

    it("uses vsplit command to create the window", function()
      native.open("codex", {})
      local found_vsplit = false
      for _, c in ipairs(cmd_calls) do
        if c:match("vsplit") then
          found_vsplit = true
          break
        end
      end
      assert.is_true(found_vsplit)
    end)

    it("uses botright placement by default (split_side=right)", function()
      native.open("codex", { split_side = "right" })
      local found = false
      for _, c in ipairs(cmd_calls) do
        if c:match("^botright") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("uses topleft placement when split_side=left", function()
      native.open("codex", { split_side = "left" })
      local found = false
      for _, c in ipairs(cmd_calls) do
        if c:match("^topleft") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("passes cwd option to termopen", function()
      native.open("codex", { cwd = "/some/path" })
      assert.are.equal("/some/path", termopen_calls[1].opts.cwd)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- close()
  -- -----------------------------------------------------------------------
  describe("close()", function()
    it("is safe to call when not open", function()
      assert.has_no.errors(function()
        native.close()
      end)
    end)

    it("stops the job (jobstop called) after open()", function()
      native.open("codex", {})
      native.close()
      assert.are.equal(1, #jobstop_calls)
    end)

    it("resets state so get_active_bufnr() returns nil", function()
      native.open("codex", {})
      assert.is_not_nil(native.get_active_bufnr())
      native.close()
      assert.is_nil(native.get_active_bufnr())
    end)

    it("calling close() twice does not error", function()
      native.open("codex", {})
      native.close()
      assert.has_no.errors(function()
        native.close()
      end)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- simple_toggle()
  -- -----------------------------------------------------------------------
  describe("simple_toggle()", function()
    it("opens terminal when none exists", function()
      native.simple_toggle("codex", {})
      assert.are.equal(1, #termopen_calls)
    end)

    it("hides terminal when it is visible", function()
      native.open("codex", {})
      -- At this point terminal is visible (open created a window)
      local b = native.get_active_bufnr()
      assert.is_not_nil(b)

      -- Hide it via simple_toggle
      native.simple_toggle("codex", {})
      -- termopen should NOT have been called again
      assert.are.equal(1, #termopen_calls)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- focus_toggle()
  -- -----------------------------------------------------------------------
  describe("focus_toggle()", function()
    it("opens terminal when none exists", function()
      native.focus_toggle("codex", {})
      assert.are.equal(1, #termopen_calls)
    end)

    it("focuses terminal when it is visible but not focused", function()
      native.open("codex", {})
      -- Switch back to original window so terminal is visible but not focused
      _G.vim._current_window = 1000
      local found_startinsert_before = 0
      for _, c in ipairs(cmd_calls) do
        if c == "startinsert" then
          found_startinsert_before = found_startinsert_before + 1
        end
      end

      native.focus_toggle("codex", {})
      local found_startinsert_after = 0
      for _, c in ipairs(cmd_calls) do
        if c == "startinsert" then
          found_startinsert_after = found_startinsert_after + 1
        end
      end
      -- focus_toggle should have issued an additional startinsert
      assert.is_true(found_startinsert_after > found_startinsert_before)
    end)
  end)
end)
