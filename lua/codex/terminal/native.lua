---Native Neovim terminal provider for codex.nvim.
---@module 'codex.terminal.native'

local M = {}

local utils = require("codex.utils")

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
    -- Search all windows for our terminal buffer
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        winid = win
        return true
      end
    end
    -- Buffer is valid but not currently displayed
    return true
  end

  return true
end

local function focus_terminal()
  if is_valid() then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  end
end

local function is_terminal_visible()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      winid = win
      return true
    end
  end

  winid = nil
  return false
end

local function hide_terminal()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, false)
    winid = nil
  end
end

local function show_hidden_terminal(effective_config, focus)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if is_terminal_visible() then
    if focus then
      focus_terminal()
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()

  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  vim.api.nvim_win_set_buf(new_winid, bufnr)
  winid = new_winid

  if focus then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(original_win)
  end

  return true
end

local function open_terminal(cmd_string, opts)
  local effective_config = {
    split_side = (opts and opts.split_side) or "right",
    split_width_percentage = (opts and opts.split_width_percentage) or 0.30,
    auto_close = (opts and opts.auto_close ~= nil) and opts.auto_close or true,
    cwd = opts and opts.cwd or nil,
  }
  local focus = utils.normalize_focus(opts and opts.focus)

  if is_valid() then
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      show_hidden_terminal(effective_config, focus)
    else
      if focus then
        focus_terminal()
      end
    end
    return
  end

  local original_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  vim.api.nvim_win_call(new_winid, function()
    vim.cmd("enew")
  end)

  local term_cmd_arg
  if cmd_string:find(" ", 1, true) then
    term_cmd_arg = vim.split(cmd_string, " ", { plain = true, trimempty = false })
  else
    term_cmd_arg = { cmd_string }
  end

  local auto_close = effective_config.auto_close
  jobid = vim.fn.termopen(term_cmd_arg, {
    cwd = effective_config.cwd,
    on_exit = function(job_id, _, _)
      vim.schedule(function()
        if job_id == jobid then
          local current_winid_for_job = winid
          local current_bufnr_for_job = bufnr

          cleanup_state()

          if not auto_close then
            return
          end

          if current_winid_for_job and vim.api.nvim_win_is_valid(current_winid_for_job) then
            if current_bufnr_for_job and vim.api.nvim_buf_is_valid(current_bufnr_for_job) then
              if vim.api.nvim_win_get_buf(current_winid_for_job) == current_bufnr_for_job then
                vim.api.nvim_win_close(current_winid_for_job, true)
              end
            else
              vim.api.nvim_win_close(current_winid_for_job, true)
            end
          end
        end
      end)
    end,
  })

  if not jobid or jobid == 0 then
    vim.notify("codex.nvim: Failed to open native terminal.", vim.log.levels.ERROR)
    vim.api.nvim_win_close(new_winid, true)
    vim.api.nvim_set_current_win(original_win)
    cleanup_state()
    return
  end

  winid = new_winid
  bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].bufhidden = "hide"

  if focus then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(original_win)
  end
end

---Open a native terminal running cmd_string.
---@param cmd_string string Command to run in the terminal
---@param opts table|nil Options: split_side, split_width_percentage, auto_close, cwd, focus
function M.open(cmd_string, opts)
  open_terminal(cmd_string, opts)
end

---Close the terminal, stop the job, and reset state.
function M.close()
  if is_valid() then
    if jobid then
      pcall(vim.fn.jobstop, jobid)
    end
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
    cleanup_state()
  end
end

---Toggle terminal visibility. Hide if visible, show hidden buffer, or open fresh.
---@param cmd_string string
---@param opts table|nil
function M.simple_toggle(cmd_string, opts)
  local has_buffer = bufnr and vim.api.nvim_buf_is_valid(bufnr)
  local is_visible = has_buffer and is_terminal_visible()

  if is_visible then
    hide_terminal()
  else
    if has_buffer then
      local effective_config = {
        split_side = (opts and opts.split_side) or "right",
        split_width_percentage = (opts and opts.split_width_percentage) or 0.30,
        auto_close = (opts and opts.auto_close ~= nil) and opts.auto_close or true,
        cwd = opts and opts.cwd or nil,
      }
      show_hidden_terminal(effective_config, true)
    else
      open_terminal(cmd_string, opts)
    end
  end
end

---Focus toggle: focus terminal if not focused; hide if focused; open if not open.
---@param cmd_string string
---@param opts table|nil
function M.focus_toggle(cmd_string, opts)
  local has_buffer = bufnr and vim.api.nvim_buf_is_valid(bufnr)
  local is_visible = has_buffer and is_terminal_visible()

  if has_buffer then
    if is_visible then
      local current_win_id = vim.api.nvim_get_current_win()
      if winid == current_win_id then
        hide_terminal()
      else
        focus_terminal()
      end
    else
      local effective_config = {
        split_side = (opts and opts.split_side) or "right",
        split_width_percentage = (opts and opts.split_width_percentage) or 0.30,
        auto_close = (opts and opts.auto_close ~= nil) and opts.auto_close or true,
        cwd = opts and opts.cwd or nil,
      }
      show_hidden_terminal(effective_config, true)
    end
  else
    open_terminal(cmd_string, opts)
  end
end

---Return the active buffer number, or nil if none.
---@return number|nil
function M.get_active_bufnr()
  if is_valid() then
    return bufnr
  end
  return nil
end

---Send text directly into the terminal's stdin channel.
---@param text string
function M.send_text(text)
  if jobid and jobid > 0 then
    vim.api.nvim_chan_send(jobid, text)
  end
end

---Always available — native Neovim terminal is built-in.
---@return boolean
function M.is_available()
  return true
end

return M
