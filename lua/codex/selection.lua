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
