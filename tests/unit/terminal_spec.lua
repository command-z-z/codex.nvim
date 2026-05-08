require("busted_setup")

describe("codex.terminal", function()
  local terminal
  local mock_native, mock_snacks, mock_external

  local function make_mock(name, available)
    local m = { _name = name, _calls = {} }
    m.is_available = function() return available end
    m.open = function(cmd, _opts) table.insert(m._calls, { "open", cmd }) end
    m.close = function() table.insert(m._calls, { "close" }) end
    m.simple_toggle = function(cmd, _opts) table.insert(m._calls, { "simple_toggle", cmd }) end
    m.focus_toggle = function(cmd, _opts) table.insert(m._calls, { "focus_toggle", cmd }) end
    m.get_active_bufnr = function() return name == "native" and 42 or nil end
    return m
  end

  before_each(function()
    package.loaded["codex.terminal"] = nil
    package.loaded["codex.terminal.native"] = nil
    package.loaded["codex.terminal.snacks"] = nil
    package.loaded["codex.terminal.external"] = nil

    mock_native   = make_mock("native", true)
    mock_snacks   = make_mock("snacks", false)
    mock_external = make_mock("external", false)

    package.loaded["codex.terminal.native"]   = mock_native
    package.loaded["codex.terminal.snacks"]   = mock_snacks
    package.loaded["codex.terminal.external"] = mock_external

    terminal = require("codex.terminal")
  end)

  describe("setup() — provider resolution", function()
    it("selects native when provider='native'", function()
      terminal.setup({ terminal = { provider = "native" }, codex_cmd = "codex" })
      assert.equals("native", terminal._get_active_provider_name())
    end)
    it("selects snacks when provider='snacks' and snacks is available", function()
      mock_snacks.is_available = function() return true end
      terminal.setup({ terminal = { provider = "snacks" }, codex_cmd = "codex" })
      assert.equals("snacks", terminal._get_active_provider_name())
    end)
    it("falls back to native when provider='snacks' but snacks unavailable", function()
      mock_snacks.is_available = function() return false end
      terminal.setup({ terminal = { provider = "snacks" }, codex_cmd = "codex" })
      assert.equals("native", terminal._get_active_provider_name())
    end)
    it("auto selects snacks when available", function()
      mock_snacks.is_available = function() return true end
      terminal.setup({ terminal = { provider = "auto" }, codex_cmd = "codex" })
      assert.equals("snacks", terminal._get_active_provider_name())
    end)
    it("auto falls back to native when snacks unavailable", function()
      mock_snacks.is_available = function() return false end
      terminal.setup({ terminal = { provider = "auto" }, codex_cmd = "codex" })
      assert.equals("native", terminal._get_active_provider_name())
    end)
    it("selects none provider when provider='none'", function()
      terminal.setup({ terminal = { provider = "none" }, codex_cmd = "codex" })
      assert.equals("none", terminal._get_active_provider_name())
    end)
  end)

  describe("delegation to active provider", function()
    before_each(function()
      terminal.setup({ terminal = { provider = "native" }, codex_cmd = "codex" })
    end)

    it("open() calls provider.open with codex_cmd", function()
      terminal.open()
      assert.equals(1, #mock_native._calls)
      assert.equals("open", mock_native._calls[1][1])
      assert.equals("codex", mock_native._calls[1][2])
    end)
    it("close() calls provider.close", function()
      terminal.close()
      assert.equals("close", mock_native._calls[1][1])
    end)
    it("simple_toggle() calls provider.simple_toggle with codex_cmd", function()
      terminal.simple_toggle()
      assert.equals("simple_toggle", mock_native._calls[1][1])
      assert.equals("codex", mock_native._calls[1][2])
    end)
    it("focus_toggle() calls provider.focus_toggle", function()
      terminal.focus_toggle()
      assert.equals("focus_toggle", mock_native._calls[1][1])
    end)
    it("get_active_terminal_bufnr() returns provider.get_active_bufnr() value", function()
      assert.equals(42, terminal.get_active_terminal_bufnr())
    end)
  end)

  it("none provider: all operations are no-ops", function()
    terminal.setup({ terminal = { provider = "none" }, codex_cmd = "codex" })
    assert.has_no.errors(function()
      terminal.open()
      terminal.close()
      terminal.simple_toggle()
      terminal.focus_toggle()
    end)
    assert.is_nil(terminal.get_active_terminal_bufnr())
  end)
end)
