local M = {}

function M.setup(opts)
  vim.notify(
    "[codex.nvim] rewrite in progress — full functionality returning in Phase 2",
    vim.log.levels.WARN
  )
  M.opts = opts or {}
end

return M
