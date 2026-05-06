require("busted_setup")

describe("rpc", function()
  local rpc_mod
  local sent_messages
  local fake_session

  local function make_fake_transport()
    sent_messages = {}
    fake_session = {
      state = "open",
      connect = function(self) end,
      send = function(self, text)
        sent_messages[#sent_messages + 1] = text
        return true
      end,
      close = function(self) self.state = "closed" end,
    }
    return {
      new = function(url, callbacks)
        fake_session._callbacks = callbacks
        return fake_session
      end,
    }
  end

  before_each(function()
    package.loaded["codex.rpc"] = nil
    package.loaded["codex.transport"] = nil
    package.preload["codex.transport"] = function() return make_fake_transport() end
    rpc_mod = require("codex.rpc")
  end)

  describe("connect", function()
    it("returns an rpc object with request/notify/respond/close methods", function()
      local rpc, err = rpc_mod.connect("ws://127.0.0.1:9999/", {})
      assert.is_nil(err)
      assert.is_function(rpc.request)
      assert.is_function(rpc.notify)
      assert.is_function(rpc.respond)
      assert.is_function(rpc.close)
    end)
  end)

  describe("notify", function()
    it("sends a JSON-RPC notification with method and params", function()
      local rpc = rpc_mod.connect("ws://127.0.0.1:9999/", {})
      rpc:notify("initialized", {})
      assert.are.equal(1, #sent_messages)
      local decoded = vim.json.decode(sent_messages[1])
      assert.are.equal("2.0", decoded.jsonrpc)
      assert.are.equal("initialized", decoded.method)
      assert.is_nil(decoded.id)
    end)
  end)

  describe("request", function()
    it("sends a JSON-RPC request with id, method, params", function()
      local rpc = rpc_mod.connect("ws://127.0.0.1:9999/", {})
      rpc:request("initialize", { clientInfo = { name = "test" } }, function() end, 5000)
      assert.are.equal(1, #sent_messages)
      local decoded = vim.json.decode(sent_messages[1])
      assert.are.equal("2.0", decoded.jsonrpc)
      assert.are.equal("initialize", decoded.method)
      assert.is_not_nil(decoded.id)
      assert.are.equal("test", decoded.params.clientInfo.name)
    end)

    it("calls callback with result when response arrives", function()
      local rpc = rpc_mod.connect("ws://127.0.0.1:9999/", {})
      local result_received
      rpc:request("initialize", {}, function(result, err)
        result_received = result
      end, 5000)

      local req_id = vim.json.decode(sent_messages[1]).id
      -- Simulate server response
      fake_session._callbacks.on_message(vim.json.encode({
        id = req_id,
        result = { codexHome = "/tmp" },
      }))
      assert.are.equal("/tmp", result_received.codexHome)
    end)

    it("calls callback with error on JSON-RPC error response", function()
      local rpc = rpc_mod.connect("ws://127.0.0.1:9999/", {})
      local err_received
      rpc:request("bad_method", {}, function(result, err)
        err_received = err
      end, 5000)
      local req_id = vim.json.decode(sent_messages[1]).id
      fake_session._callbacks.on_message(vim.json.encode({
        id = req_id,
        error = { code = -32601, message = "Method not found" },
      }))
      assert.are.equal(-32601, err_received.code)
    end)
  end)

  describe("respond", function()
    it("sends a JSON-RPC response for a server-initiated request", function()
      local rpc = rpc_mod.connect("ws://127.0.0.1:9999/", {
        on_request = function(method, params, respond)
          respond({ decision = "denied" })
        end,
      })
      -- Simulate a server→client request
      fake_session._callbacks.on_message(vim.json.encode({
        jsonrpc = "2.0",
        id = 99,
        method = "applyPatchApproval",
        params = {},
      }))
      -- Our on_request handler called respond({ decision = "denied" })
      -- That should have sent a response
      local response_msg = vim.json.decode(sent_messages[#sent_messages])
      assert.are.equal(99, response_msg.id)
      assert.are.equal("denied", response_msg.result.decision)
    end)
  end)

  describe("notifications", function()
    it("dispatches on_notification for server notifications", function()
      local notif_method, notif_params
      local rpc = rpc_mod.connect("ws://127.0.0.1:9999/", {
        on_notification = function(method, params)
          notif_method = method
          notif_params = params
        end,
      })
      fake_session._callbacks.on_message(vim.json.encode({
        method = "turn/completed",
        params = { threadId = "abc" },
      }))
      assert.are.equal("turn/completed", notif_method)
      assert.are.equal("abc", notif_params.threadId)
    end)
  end)
end)
