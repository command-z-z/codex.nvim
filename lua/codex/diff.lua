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

-- ── UI stubs (replaced in Task 3) ────────────────────────────────

function M._open_ui() end

function M._refresh_buf() end

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
