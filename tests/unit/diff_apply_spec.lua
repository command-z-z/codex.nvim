-- tests/unit/diff_apply_spec.lua
require("busted_setup")

describe("codex.handlers", function()
  local handlers
  local diff_mock

  before_each(function()
    package.loaded["codex.handlers.init"] = nil
    package.loaded["codex.handlers.diff_apply"] = nil

    diff_mock = {
      open_calls = {},
      open = function(patch, respond_fn, opts)
        table.insert(diff_mock.open_calls, { patch = patch, respond_fn = respond_fn, opts = opts })
      end,
    }
    package.preload["codex.diff"] = function() return diff_mock end
    package.preload["codex.init"] = function()
      return { state = { config = { diff_opts = { layout = "vertical" } } } }
    end

    handlers = require("codex.handlers.init")
  end)

  after_each(function()
    package.preload["codex.diff"] = nil
    package.preload["codex.init"] = nil
    package.loaded["codex.diff"] = nil
    package.loaded["codex.init"] = nil
  end)

  -- ── handlers/init.lua — dispatcher ────────────────────────────
  describe("handlers/init.lua", function()
    it("handle_notification: unknown method is a no-op", function()
      assert.has_no.errors(function()
        handlers.handle_notification("$/unknown", {})
      end)
    end)

    it("handle_request: unknown method responds with error code -32601", function()
      local err = nil
      handlers.handle_request("$/unknown", {}, function(_, e) err = e end)
      assert.is_not_nil(err)
      assert.equals(-32601, err.code)
    end)

    it("handle_notification: calls registered handler's on_notification", function()
      local called_params = nil
      handlers.register("$/test", {
        on_notification = function(params) called_params = params end,
      })
      handlers.handle_notification("$/test", { x = 42 })
      assert.equals(42, called_params.x)
    end)

    it("handle_request: calls registered handler's on_request with respond", function()
      local got_respond = nil
      handlers.register("$/test", {
        on_request = function(_, respond) got_respond = respond end,
      })
      local my_respond = function() end
      handlers.handle_request("$/test", {}, my_respond)
      assert.equals(my_respond, got_respond)
    end)

    it("handle_notification: no error when handler has no on_notification field", function()
      handlers.register("$/test", { on_request = function() end })
      assert.has_no.errors(function()
        handlers.handle_notification("$/test", {})
      end)
    end)

    it("handle_request: nil respond is safe for unknown method", function()
      assert.has_no.errors(function()
        handlers.handle_request("$/unknown", {}, nil)
      end)
    end)
  end)

  -- ── handlers/diff_apply.lua ────────────────────────────────────
  describe("handlers/diff_apply.lua", function()
    local diff_apply

    before_each(function()
      package.loaded["codex.handlers.diff_apply"] = nil
      diff_apply = require("codex.handlers.diff_apply")
    end)

    it("on_request calls diff.open with params.patch", function()
      local respond = function() end
      diff_apply.on_request({ patch = "the patch" }, respond)
      assert.equals(1, #diff_mock.open_calls)
      assert.equals("the patch", diff_mock.open_calls[1].patch)
    end)

    it("on_request passes the respond callback to diff.open", function()
      local respond = function() end
      diff_apply.on_request({ patch = "p" }, respond)
      assert.equals(respond, diff_mock.open_calls[1].respond_fn)
    end)

    it("on_request falls back to params.diff when no patch key", function()
      diff_apply.on_request({ diff = "diff text" }, function() end)
      assert.equals("diff text", diff_mock.open_calls[1].patch)
    end)

    it("on_request falls back to empty string when both missing", function()
      diff_apply.on_request({}, function() end)
      assert.equals("", diff_mock.open_calls[1].patch)
    end)

    it("on_request passes diff_opts from config", function()
      diff_apply.on_request({ patch = "p" }, function() end)
      assert.equals("vertical", diff_mock.open_calls[1].opts.layout)
    end)

    it("on_notification calls diff.open with nil respond_fn", function()
      diff_apply.on_notification({ patch = "patch data" })
      assert.equals(1, #diff_mock.open_calls)
      assert.is_nil(diff_mock.open_calls[1].respond_fn)
    end)

    it("on_notification passes the patch string", function()
      diff_apply.on_notification({ patch = "notif patch" })
      assert.equals("notif patch", diff_mock.open_calls[1].patch)
    end)

    it("on_notification passes diff_opts from config", function()
      diff_apply.on_notification({ patch = "p" })
      assert.equals("vertical", diff_mock.open_calls[1].opts.layout)
    end)

    it("on_request is safe when params is nil", function()
      assert.has_no.errors(function()
        diff_apply.on_request(nil, function() end)
      end)
    end)

    it("on_notification is safe when params is nil", function()
      assert.has_no.errors(function()
        diff_apply.on_notification(nil)
      end)
    end)
  end)
end)
