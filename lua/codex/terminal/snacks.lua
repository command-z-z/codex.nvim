-- lua/codex/terminal/snacks.lua
local snacks_ok, Snacks = pcall(require, "snacks")

local M = {}

local terminal = nil

local function shellescape(arg)
  if vim.fn and vim.fn.shellescape then
    return vim.fn.shellescape(arg)
  end
  return "'" .. arg:gsub("'", [['"'"']]) .. "'"
end

local function shell_join(cmd)
  if type(cmd) ~= "table" then
    return cmd
  end
  local parts = {}
  for _, arg in ipairs(cmd) do
    parts[#parts + 1] = shellescape(tostring(arg))
  end
  return table.concat(parts, " ")
end

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
  if not M.is_available() then return end
  terminal = Snacks.terminal.toggle(shell_join(cmd), build_snacks_opts(opts))
end

function M.close()
  if not M.is_available() then return end
  if terminal then
    terminal:close()
    terminal = nil
  end
end

function M.simple_toggle(cmd, opts)
  if not M.is_available() then return end
  terminal = Snacks.terminal.toggle(shell_join(cmd), build_snacks_opts(opts))
end

function M.focus_toggle(cmd, opts)
  if not M.is_available() then return end
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
  terminal = Snacks.terminal.toggle(shell_join(cmd), build_snacks_opts(opts))
end

function M.send_text(text)
  if not terminal then return end
  local bufnr = terminal.buf
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local ok, chan = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if ok and chan and chan > 0 then
    vim.api.nvim_chan_send(chan, text)
  end
end

function M._get_terminal_for_test()
  return terminal
end

return M
