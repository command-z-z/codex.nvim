-- lua/codex/diff_patch.lua
-- Pure-Lua unified-diff patch applier. Given original file lines plus parsed
-- hunks (from codex.diff::parse), produces the post-patch lines in-memory. No
-- writes to disk. Used by the diffsplit UI to render the right-hand buffer.
local M = {}

-- Parse "@@ -os,oc +ns,nc @@" → 4 numbers (oc/nc default 1 when omitted).
function M.parse_hunk_header(header)
  local os_, oc, ns, nc = tostring(header or "")
    :match("^@@%s*%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s*@@")
  if not os_ then return nil end
  return tonumber(os_),
         tonumber(oc ~= "" and oc or "1"),
         tonumber(ns),
         tonumber(nc ~= "" and nc or "1")
end

-- Apply parsed hunks to an array of original lines. Returns
--   new_lines, true, nil          on success
--   nil,       false, err_msg     on failure (bad header, context mismatch,
--                                            out-of-range, delete mismatch).
function M.apply_hunks(original_lines, hunks)
  original_lines = original_lines or {}
  local result, orig_idx = {}, 1
  for hi, hunk in ipairs(hunks or {}) do
    local old_start = M.parse_hunk_header(hunk.header)
    if not old_start then
      return nil, false, "bad hunk header: " .. tostring(hunk.header)
    end
    -- Copy unchanged lines [orig_idx, old_start) verbatim.
    while orig_idx < old_start do
      if orig_idx > #original_lines then
        return nil, false, ("hunk %d: out of range"):format(hi)
      end
      result[#result + 1] = original_lines[orig_idx]
      orig_idx = orig_idx + 1
    end
    for _, line in ipairs(hunk.lines or {}) do
      local prefix = line:sub(1, 1)
      local body   = line:sub(2)
      if prefix == " " then
        if original_lines[orig_idx] ~= body then
          return nil, false, ("hunk %d: context mismatch at line %d"):format(hi, orig_idx)
        end
        result[#result + 1] = body
        orig_idx = orig_idx + 1
      elseif prefix == "+" then
        result[#result + 1] = body
      elseif prefix == "-" then
        if original_lines[orig_idx] ~= body then
          return nil, false, ("hunk %d: delete mismatch at line %d"):format(hi, orig_idx)
        end
        orig_idx = orig_idx + 1
      elseif prefix == "\\" then
        -- "\ No newline at end of file" — skip
      end
    end
  end
  while orig_idx <= #original_lines do
    result[#result + 1] = original_lines[orig_idx]
    orig_idx = orig_idx + 1
  end
  return result, true, nil
end

local function read_lines(abs_path)
  local fd = io.open(abs_path, "rb")
  if not fd then return nil end
  local lines = {}
  for line in fd:lines() do lines[#lines + 1] = line end
  fd:close()
  return lines
end

-- High-level: decide based on file.kind whether to read disk, then apply.
--   binary  → error "binary" (caller should skip preview)
--   delete  → {} (right side is empty)
--   new     → apply hunks to empty original (file may not exist on disk)
--   modify  → read disk + apply hunks
-- Returns new_lines, ok, err_msg with the same convention as apply_hunks.
function M.compute_new_lines(file, abs_path)
  if file.binary then return nil, false, "binary" end
  if file.kind == "delete" then return {}, true, nil end
  local original_lines = {}
  if file.kind == "modify" then
    original_lines = read_lines(abs_path)
    if not original_lines then
      return nil, false, "cannot read " .. tostring(abs_path)
    end
  end
  return M.apply_hunks(original_lines, file.hunks)
end

return M
