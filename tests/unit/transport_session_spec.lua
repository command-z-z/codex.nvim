require("busted_setup")

describe("transport.session", function()
  local session_mod
  local mock_tcp_calls

  -- Replace transport.tcp with a controllable fake
  local function make_fake_tcp()
    mock_tcp_calls = { writes = {}, closed = false }
    local fake_conn = {
      state = "connected",
      write = function(self, data, cb)
        mock_tcp_calls.writes[#mock_tcp_calls.writes + 1] = data
        if cb then cb() end
      end,
      close = function(self)
        mock_tcp_calls.closed = true
        self.state = "closed"
      end,
    }
    local fake_tcp = {
      new_connection = function(host, port, cbs)
        fake_conn._callbacks = cbs
        vim.schedule(function() cbs.on_connect() end)
        return fake_conn
      end,
      fake_conn = fake_conn,
    }
    return fake_tcp
  end

  before_each(function()
    package.loaded["codex.transport.session"] = nil
    package.loaded["codex.transport.tcp"] = nil
    package.loaded["codex.transport.handshake"] = nil
    package.loaded["codex.transport.frame"] = nil
    package.loaded["codex.transport.utils"] = nil
    local fake_tcp = make_fake_tcp()
    package.preload["codex.transport.tcp"] = function() return fake_tcp end
    session_mod = require("codex.transport.session")
  end)

  it("starts in idle state", function()
    local s = session_mod.new("ws://127.0.0.1:12345/")
    assert.are.equal("idle", s.state)
  end)

  it("returns nil + error for invalid URL", function()
    local s, err = session_mod.new("not-a-url")
    assert.is_nil(s)
    assert.is_not_nil(err)
  end)

  it("transitions to connecting then handshaking after connect()", function()
    local s = session_mod.new("ws://127.0.0.1:12345/")
    s:connect()
    -- After connect() the tcp.new_connection is called; on_connect fires via vim.schedule
    -- vim.schedule in our mock runs immediately
    assert.are.equal("handshaking", s.state)
  end)

  it("sends HTTP upgrade request when on_connect fires", function()
    local s = session_mod.new("ws://127.0.0.1:12345/")
    s:connect()
    assert.are.equal(1, #mock_tcp_calls.writes)
    assert.is_truthy(mock_tcp_calls.writes[1]:find("Upgrade: websocket", 1, true))
  end)

  it("transitions to open after receiving a valid 101 response", function()
    local on_open_called = false
    local s = session_mod.new("ws://127.0.0.1:12345/", {
      on_open = function() on_open_called = true end,
    })
    s:connect()

    -- Feed a minimal 101 response (accept key doesn't need to be validated strictly here)
    local response_101 = table.concat({
      "HTTP/1.1 101 Switching Protocols",
      "connection: upgrade",
      "upgrade: websocket",
      "sec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
      "", "",
    }, "\r\n")
    s:_on_data(response_101)

    assert.are.equal("open", s.state)
    assert.is_true(on_open_called)
  end)

  it("calls on_error and sets state to closed on bad handshake", function()
    local err_msg
    local s = session_mod.new("ws://127.0.0.1:12345/", {
      on_error = function(e) err_msg = e end,
    })
    s:connect()
    s:_on_data("HTTP/1.1 403 Forbidden\r\n\r\n")
    assert.are.equal("closed", s.state)
    assert.is_not_nil(err_msg)
  end)

  it("send() returns false when not open", function()
    local s = session_mod.new("ws://127.0.0.1:12345/")
    local ok, err = s:send("hello")
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("dispatches on_message for TEXT frames when open", function()
    local received
    local s = session_mod.new("ws://127.0.0.1:12345/", {
      on_message = function(msg) received = msg end,
    })
    s:connect()
    local r101 = "HTTP/1.1 101 Switching Protocols\r\nconnection: upgrade\r\nupgrade: websocket\r\nsec-websocket-accept: x\r\n\r\n"
    s:_on_data(r101)

    -- Build a real unmasked server→client TEXT frame
    local frame = require("codex.transport.frame")
    local f = frame.create_frame(frame.OPCODE.TEXT, "hello", true, false)
    s:_on_data(f)

    assert.are.equal("hello", received)
  end)
end)
