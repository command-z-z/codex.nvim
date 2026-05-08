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
