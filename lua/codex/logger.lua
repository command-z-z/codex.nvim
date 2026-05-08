-- lua/codex/logger.lua
local M = {}

M.level = vim.log.levels.WARN

local STR_TO_LEVEL = {
  trace = 0,
  debug = vim.log.levels.DEBUG,
  info  = vim.log.levels.INFO,
  warn  = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

function M.set_level(level)
  if type(level) == "string" then
    M.level = STR_TO_LEVEL[level] or vim.log.levels.WARN
  else
    M.level = level
  end
end

local function log(num_level, msg)
  if num_level < M.level then return end
  vim.notify("[codex] " .. tostring(msg), num_level, { title = "codex.nvim" })
end

function M.trace(msg) log(0,                       msg) end
function M.debug(msg) log(vim.log.levels.DEBUG,    msg) end
function M.info(msg)  log(vim.log.levels.INFO,     msg) end
function M.warn(msg)  log(vim.log.levels.WARN,     msg) end
function M.error(msg) log(vim.log.levels.ERROR,    msg) end

return M
