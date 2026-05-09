require("busted_setup")

describe("codex.app_server", function()
  local app_server
  local requests
  local jobstart_calls
  local fake_rpc

  before_each(function()
    package.loaded["codex.app_server"] = nil
    package.loaded["codex.rpc"] = nil

    requests = {}
    jobstart_calls = {}

    fake_rpc = {
      client = { state = "connected" },
      request = function(_, method, params, callback)
        table.insert(requests, { method = method, params = params })
        if method == "initialize" then
          callback({}, nil)
        elseif method == "thread/start" then
          callback({ thread = { id = "thread-1" } }, nil)
        elseif method == "turn/start" then
          callback({ turn = { id = "turn-1" } }, nil)
        end
      end,
      notify = function() end,
      close = function() end,
    }

    package.preload["codex.rpc"] = function()
      return {
        connect = function(_, opts)
          opts.on_open(fake_rpc)
          return fake_rpc, nil
        end,
      }
    end

    _G.vim.fn.jobstart = function(cmd, opts)
      table.insert(jobstart_calls, { cmd = cmd, opts = opts })
      return 1
    end

    app_server = require("codex.app_server")
  end)

  after_each(function()
    if app_server then
      app_server.stop()
    end
    package.preload["codex.rpc"] = nil
    package.loaded["codex.rpc"] = nil
    package.loaded["codex.app_server"] = nil
  end)

  it("sends CodexAdd mentions as turn/start mention input", function()
    app_server.configure({
      codex_cmd = "mycodex",
      port_range = { min = 12345, max = 12345 },
      approval = { policy = "prompt", sandbox = "read-only" },
    })

    app_server.add_mentions({ "lua/foo.lua:2-4" }, { model = "gpt-test" })

    assert.equals("mycodex", jobstart_calls[1].cmd[1])
    assert.equals("app-server", jobstart_calls[1].cmd[2])
    assert.equals("--listen", jobstart_calls[1].cmd[3])
    assert.equals("ws://127.0.0.1:12345", jobstart_calls[1].cmd[4])

    assert.equals("initialize", requests[1].method)
    assert.equals("thread/start", requests[2].method)
    assert.equals("on-request", requests[2].params.approvalPolicy)
    assert.equals("read-only", requests[2].params.sandbox)
    assert.equals("gpt-test", requests[2].params.model)

    assert.equals("turn/start", requests[3].method)
    assert.equals("thread-1", requests[3].params.threadId)
    assert.equals("on-request", requests[3].params.approvalPolicy)
    assert.equals("read-only", requests[3].params.sandboxPolicy)
    assert.equals("gpt-test", requests[3].params.model)
    assert.same({
      { type = "text", text = "Add the referenced file context." },
      { type = "mention", name = "foo.lua", path = "lua/foo.lua" },
      { type = "text", text = "Use lines 2-4 from lua/foo.lua." },
    }, requests[3].params.input)
  end)

  it("keeps approval requests enabled for auto-allow so the handler can approve them", function()
    app_server.configure({
      port_range = { min = 12345, max = 12345 },
      approval = { policy = "auto-allow" },
    })

    app_server.add_mentions({ "lua/bar.lua" })

    assert.equals("on-request", requests[2].params.approvalPolicy)
    assert.equals("on-request", requests[3].params.approvalPolicy)
  end)

  it("keeps approval requests enabled for auto-deny so the handler can deny them", function()
    app_server.configure({
      port_range = { min = 12345, max = 12345 },
      approval = { policy = "auto-deny" },
    })

    app_server.add_mentions({ "lua/bar.lua" })

    assert.equals("on-request", requests[2].params.approvalPolicy)
    assert.equals("on-request", requests[3].params.approvalPolicy)
  end)
end)
