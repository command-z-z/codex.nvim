-- lua/codex/utils.lua
local M = {}

---Normalizes focus parameter, defaulting to true for backward compatibility.
---@param focus boolean?
---@return boolean
function M.normalize_focus(focus)
  if focus == nil then
    return true
  else
    return focus
  end
end

return M
