require("busted_setup")

describe("transport.handshake", function()
  local handshake

  before_each(function()
    package.loaded["codex.transport.utils"] = nil
    package.loaded["codex.transport.handshake"] = nil
    handshake = require("codex.transport.handshake")
  end)

  describe("parse_url", function()
    it("parses ws://host:port/ correctly", function()
      local parsed, err = handshake.parse_url("ws://127.0.0.1:45123/")
      assert.is_nil(err)
      assert.are.equal("127.0.0.1", parsed.host)
      assert.are.equal(45123, parsed.port)
      assert.are.equal("/", parsed.path)
    end)

    it("defaults path to / when omitted", function()
      local parsed, err = handshake.parse_url("ws://localhost:8080")
      assert.is_nil(err)
      assert.are.equal("/", parsed.path)
    end)

    it("returns nil + error for non-ws URL", function()
      local parsed, err = handshake.parse_url("http://example.com")
      assert.is_nil(parsed)
      assert.is_not_nil(err)
    end)

    it("returns nil + error for malformed URL", function()
      local parsed, err = handshake.parse_url("not-a-url")
      assert.is_nil(parsed)
      assert.is_not_nil(err)
    end)
  end)

  describe("build_request", function()
    it("includes all required WebSocket upgrade headers", function()
      local req = handshake.build_request("127.0.0.1", 45123, "/", "testkey==")
      assert.is_truthy(req:find("GET / HTTP/1.1", 1, true))
      assert.is_truthy(req:find("Host: 127.0.0.1:45123", 1, true))
      assert.is_truthy(req:find("Upgrade: websocket", 1, true))
      assert.is_truthy(req:find("Connection: Upgrade", 1, true))
      assert.is_truthy(req:find("Sec-WebSocket-Key: testkey==", 1, true))
      assert.is_truthy(req:find("Sec-WebSocket-Version: 13", 1, true))
    end)

    it("ends with double CRLF (HTTP header terminator)", function()
      local req = handshake.build_request("host", 80, "/", "k")
      assert.are.equal("\r\n\r\n", req:sub(-4))
    end)
  end)

  describe("parse_response", function()
    local valid_101 = table.concat({
      "HTTP/1.1 101 Switching Protocols",
      "connection: upgrade",
      "upgrade: websocket",
      "sec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
      "",
      "",
    }, "\r\n")

    it("accepts valid 101 response and extracts accept key", function()
      local ok, accept = handshake.parse_response(valid_101)
      assert.is_true(ok)
      assert.are.equal("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept)
    end)

    it("rejects HTTP 400", function()
      local ok, err = handshake.parse_response("HTTP/1.1 400 Bad Request\r\n\r\n")
      assert.is_false(ok)
      assert.is_truthy(err:find("400"))
    end)

    it("rejects garbage response", function()
      local ok, err = handshake.parse_response("not http")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe("validate_accept", function()
    it("accepts the RFC 6455 test vector", function()
      local client_key = "dGhlIHNhbXBsZSBub25jZQ=="
      local server_accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
      assert.is_true(handshake.validate_accept(client_key, server_accept))
    end)

    it("rejects a wrong accept key", function()
      local client_key = "dGhlIHNhbXBsZSBub25jZQ=="
      assert.is_false(handshake.validate_accept(client_key, "wrongkey=="))
    end)
  end)
end)
