local M = {}

---Open a TCP connection to host:port.
---Returns a connection object with :write() and :close().
---All callbacks are scheduled on the Neovim event loop (vim.schedule).
---
---@param host string
---@param port number
---@param callbacks table { on_connect, on_data, on_close, on_error }
---@return table connection
function M.new_connection(host, port, callbacks)
  local uv = vim.uv or vim.loop
  local tcp = uv.new_tcp()
  local conn = {
    tcp = tcp,
    state = "connecting",
  }

  tcp:connect(host, port, function(err)
    if err then
      conn.state = "closed"
      if callbacks.on_error then
        vim.schedule(function() callbacks.on_error(err) end)
      end
      return
    end

    conn.state = "connected"
    if callbacks.on_connect then
      vim.schedule(function() callbacks.on_connect() end)
    end

    tcp:read_start(function(read_err, data)
      if read_err then
        if callbacks.on_error then
          vim.schedule(function() callbacks.on_error(read_err) end)
        end
        return
      end
      if not data then
        conn.state = "closed"
        if callbacks.on_close then
          vim.schedule(function() callbacks.on_close() end)
        end
        return
      end
      if callbacks.on_data then
        vim.schedule(function() callbacks.on_data(data) end)
      end
    end)
  end)

  function conn:write(data, callback)
    if self.state == "closed" then return end
    self.tcp:write(data, callback)
  end

  function conn:close()
    if self.state == "closed" then return end
    self.state = "closed"
    pcall(function() self.tcp:close() end)
  end

  return conn
end

return M
