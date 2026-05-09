-- lua/codex/diff.lua
local M = {}

-- ── Pure helpers ──────────────────────────────────────────────────

local function starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function split_lines(text)
  local lines = {}
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

-- ── Parser ────────────────────────────────────────────────────────

local function new_file()
  return { header = {}, hunks = {}, binary = false }
end

function M.parse(patch)
  local files = {}
  local current, current_hunk
  for _, line in ipairs(split_lines(patch or "")) do
    if starts_with(line, "diff --git ") then
      current = new_file()
      current.header[#current.header + 1] = line
      files[#files + 1] = current
      current_hunk = nil
    elseif current and starts_with(line, "@@") then
      current_hunk = { header = line, lines = {}, accepted = true }
      current.hunks[#current.hunks + 1] = current_hunk
    elseif current and (starts_with(line, "Binary files ") or starts_with(line, "GIT binary patch")) then
      current.binary = true
      current.header[#current.header + 1] = line
      current_hunk = nil
    elseif current_hunk then
      current_hunk.lines[#current_hunk.lines + 1] = line
    elseif current then
      current.header[#current.header + 1] = line
    end
  end
  return files
end

function M.set_accepted(files, file_idx, hunk_idx, accepted)
  local file = files[file_idx]
  if not file then return false end
  if hunk_idx then
    if not file.hunks[hunk_idx] then return false end
    file.hunks[hunk_idx].accepted = accepted
  else
    for _, hunk in ipairs(file.hunks) do
      hunk.accepted = accepted
    end
  end
  return true
end

function M.render(files, accepted_only)
  local out = {}
  for _, file in ipairs(files or {}) do
    local visible = {}
    for _, hunk in ipairs(file.hunks) do
      if not accepted_only or hunk.accepted then
        visible[#visible + 1] = hunk
      end
    end
    if #visible > 0 then
      for _, h in ipairs(file.header) do out[#out + 1] = h end
      for _, hunk in ipairs(visible) do
        out[#out + 1] = hunk.header
        for _, line in ipairs(hunk.lines) do out[#out + 1] = line end
      end
    end
  end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

-- ── Session state ──────────────────────────────────────────────────

M.state = {
  pending = nil,  -- { files, respond_fn, buf, win, hunk_map, hunk_starts, config }
}

function M.has_pending()
  return M.state.pending ~= nil
end

function M.get_pending()
  return M.state.pending
end

function M.open(patch, respond_fn, opts)
  opts = opts or {}
  if M.has_pending() then
    M._close_windows()
    M.state.pending = nil
  end
  local files = M.parse(patch)
  if #files == 0 then
    if respond_fn then respond_fn({ accepted = true, patch = "" }, nil) end
    return
  end
  M.state.pending = {
    files = files,
    respond_fn = respond_fn,
    buf = nil,
    win = nil,
    hunk_map = {},
    hunk_starts = {},
    config = opts,
  }
  M._open_ui()
end

function M.accept_all()
  local p = M.state.pending
  if not p then return end
  for i = 1, #p.files do
    M.set_accepted(p.files, i, nil, true)
  end
  local patch = M.render(p.files, true)
  local respond_fn = p.respond_fn
  M._close_windows()
  M.state.pending = nil
  if respond_fn then respond_fn({ accepted = true, patch = patch }, nil) end
end

function M.deny_all()
  local p = M.state.pending
  if not p then return end
  local respond_fn = p.respond_fn
  M._close_windows()
  M.state.pending = nil
  if respond_fn then respond_fn({ accepted = false }, nil) end
end

function M.accept_hunk(file_idx, hunk_idx)
  local p = M.state.pending
  if not p then return end
  M.set_accepted(p.files, file_idx, hunk_idx, true)
  M._refresh_buf()
end

function M.reject_hunk(file_idx, hunk_idx)
  local p = M.state.pending
  if not p then return end
  M.set_accepted(p.files, file_idx, hunk_idx, false)
  M._refresh_buf()
end

-- ── UI ────────────────────────────────────────────────────────────

local SKIP_FILETYPES = {
  NvimTree = true, ["neo-tree"] = true, oil = true,
  aerial = true, lazy = true,
}

function M._find_edit_window()
  local wins = vim.api.nvim_list_wins()
  for _, winid in ipairs(wins) do
    local cfg = vim.api.nvim_win_get_config(winid)
    local is_floating = type(cfg.relative) == "string" and cfg.relative ~= ""
    if not is_floating then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local bt = vim.api.nvim_buf_get_option(bufnr, "buftype") or ""
      local ft = vim.api.nvim_buf_get_option(bufnr, "filetype") or ""
      if bt ~= "terminal" and bt ~= "nofile" and not SKIP_FILETYPES[ft] then
        return winid
      end
    end
  end
  return vim.api.nvim_get_current_win()
end

function M._open_ui()
  local p = M.state.pending
  if not p then return end
  local cfg = p.config or {}

  local target_win = M._find_edit_window()
  vim.api.nvim_set_current_win(target_win)

  if cfg.open_in_new_tab then
    vim.cmd("tabnew")
  elseif cfg.layout == "horizontal" then
    vim.cmd("split")
  else
    vim.cmd("vsplit")
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_name(buf, "CodexDiff")
  vim.api.nvim_buf_set_option(buf, "filetype", "diff")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  p.buf = buf
  p.win = win

  M._refresh_buf()
  M._set_keymaps(buf)
end

function M._refresh_buf()
  local p = M.state.pending
  if not p or not p.buf then return end

  local lines = {}
  local hunk_map = {}
  local hunk_starts = {}

  for fi, file in ipairs(p.files) do
    for _, h in ipairs(file.header) do
      lines[#lines + 1] = h
    end
    for hi, hunk in ipairs(file.hunks) do
      local marker = hunk.accepted and " [ACCEPT]" or " [REJECT]"
      lines[#lines + 1] = hunk.header .. marker
      local header_lnum = #lines
      hunk_map[header_lnum] = { file_idx = fi, hunk_idx = hi }
      hunk_starts[#hunk_starts + 1] = header_lnum
      for _, hunk_line in ipairs(hunk.lines) do
        lines[#lines + 1] = hunk_line
        hunk_map[#lines] = { file_idx = fi, hunk_idx = hi }
      end
    end
  end

  p.hunk_map = hunk_map
  p.hunk_starts = hunk_starts

  vim.api.nvim_buf_set_option(p.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(p.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(p.buf, "modifiable", false)
end

function M._accept_hunk_at_cursor()
  local p = M.state.pending
  if not p or not p.hunk_map or not p.win then return end
  local cursor = vim.api.nvim_win_get_cursor(p.win)
  local entry = p.hunk_map[cursor[1]]
  if entry then
    M.set_accepted(p.files, entry.file_idx, entry.hunk_idx, true)
    M._refresh_buf()
  end
end

function M._reject_hunk_at_cursor()
  local p = M.state.pending
  if not p or not p.hunk_map or not p.win then return end
  local cursor = vim.api.nvim_win_get_cursor(p.win)
  local entry = p.hunk_map[cursor[1]]
  if entry then
    M.set_accepted(p.files, entry.file_idx, entry.hunk_idx, false)
    M._refresh_buf()
  end
end

function M._goto_next_hunk()
  local p = M.state.pending
  if not p or not p.win or not p.hunk_starts then return end
  local cursor = vim.api.nvim_win_get_cursor(p.win)
  local cur_line = cursor[1]
  for _, lnum in ipairs(p.hunk_starts) do
    if lnum > cur_line then
      vim.api.nvim_win_set_cursor(p.win, { lnum, 0 })
      return
    end
  end
end

function M._goto_prev_hunk()
  local p = M.state.pending
  if not p or not p.win or not p.hunk_starts then return end
  local cursor = vim.api.nvim_win_get_cursor(p.win)
  local cur_line = cursor[1]
  local target = nil
  for _, lnum in ipairs(p.hunk_starts) do
    if lnum < cur_line then target = lnum end
  end
  if target then
    vim.api.nvim_win_set_cursor(p.win, { target, 0 })
  end
end

function M._set_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, noremap = true, silent = true })
  end
  map("a",    function() M._accept_hunk_at_cursor() end, "Accept hunk at cursor")
  map("r",    function() M._reject_hunk_at_cursor() end, "Reject hunk at cursor")
  map("A",    function() M.accept_all() end,              "Accept all hunks")
  map("R",    function() M.deny_all()   end,              "Reject all hunks")
  map("n",    function() M._goto_next_hunk() end,         "Next hunk")
  map("p",    function() M._goto_prev_hunk() end,         "Previous hunk")
  map("q",    function() M.deny_all()   end,              "Quit/deny diff")
  map("<CR>", function() M.accept_all() end,              "Accept all")
end

function M._close_windows()
  local p = M.state.pending
  if not p then return end
  if p.win and vim.api.nvim_win_is_valid(p.win) then
    vim.api.nvim_win_close(p.win, true)
  end
  if p.buf and vim.api.nvim_buf_is_valid(p.buf) then
    pcall(vim.api.nvim_buf_delete, p.buf, { force = true })
  end
end

return M
