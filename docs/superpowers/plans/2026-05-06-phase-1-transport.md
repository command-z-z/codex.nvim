# Phase 1 — Transport Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure-Lua WebSocket client (`transport/`) that connects to `codex app-server`, plus a JSON-RPC 2.0 layer (`rpc.lua`) and process supervisor (`app_server.lua`) — all zero plenary/nui dependencies.

**Architecture:** Eight focused modules. Pure-Lua modules (`utils`, `frame`, `handshake`) have no Neovim dependency and are fully unit-testable with standalone busted. Vim-dependent modules (`tcp`, `session`, `rpc`, `app_server`) use the ported vim mock. `session.lua` owns the state machine; `rpc.lua` owns the JSON-RPC protocol; `app_server.lua` owns the subprocess lifecycle. `transport/init.lua` is a thin facade over `session.lua`.

**Tech Stack:** Neovim ≥ 0.10, Lua 5.1, `vim.loop` (≡ `vim.uv`) for async TCP, `vim.fn.jobstart` for subprocess, busted for tests, custom vim mock (no plenary).

**Reference files (read before writing):**
- `claudecode.nvim/lua/claudecode/server/utils.lua` — SHA-1 + Base64 source (port verbatim, change module name)
- `claudecode.nvim/lua/claudecode/server/frame.lua` — RFC 6455 codec (port verbatim, change require path)
- `claudecode.nvim/tests/mocks/vim.lua` — vim API mock (port verbatim, change module path)
- `claudecode.nvim/tests/busted_setup.lua` — test helpers (port verbatim, change module path)
- Stash `stash@{0}^3:lua/codex/websocket.lua` — working WS client prototype (reference for tcp + session)
- Stash `stash@{0}^3:lua/codex/rpc.lua` — working RPC prototype (port, change require path)
- Stash `stash@{0}^3:lua/codex/app_server.lua` — working supervisor prototype (port, change require path)

---

## Pre-Flight

```bash
cd /home/eugene/Desktop/MyRepo/codex.nvim
git status        # should be clean on refactor/mirror-claudecode
ls lua/codex/     # should contain only init.lua
make test         # should print "No test files..." (0 failures)
```

---

## File Map

| File | Role | Depends on |
|------|------|------------|
| `lua/codex/transport/utils.lua` | SHA-1, Base64, uint helpers, mask | nothing |
| `lua/codex/transport/frame.lua` | RFC 6455 encode/decode | transport.utils |
| `lua/codex/transport/handshake.lua` | HTTP upgrade request/response, URL parser | transport.utils |
| `lua/codex/transport/tcp.lua` | vim.loop TCP client factory | vim.uv |
| `lua/codex/transport/session.lua` | State machine + 30s heartbeat | tcp, handshake, frame, utils |
| `lua/codex/transport/init.lua` | Facade over session | transport.session |
| `lua/codex/rpc.lua` | JSON-RPC 2.0 | transport (init), vim.json, vim.uv |
| `lua/codex/app_server.lua` | Subprocess supervisor | config, rpc, vim.fn.jobstart |
| `tests/busted_setup.lua` | expect helpers + vim mock loader | mocks.vim |
| `tests/mocks/vim.lua` | Neovim API stub | nothing |
| `tests/unit/transport_utils_spec.lua` | Unit tests | transport.utils |
| `tests/unit/transport_frame_spec.lua` | Unit tests | transport.frame |
| `tests/unit/transport_handshake_spec.lua` | Unit tests | transport.handshake |
| `tests/unit/transport_session_spec.lua` | Unit tests | transport.session, mocks.vim |
| `tests/unit/rpc_spec.lua` | Unit tests | rpc, mocks.vim |

---

## Task 1: Port test infrastructure

**Files:**
- Create: `tests/busted_setup.lua`
- Modify: `tests/mocks/vim.lua` (replace stub with full port)

- [ ] **Step 1: Create `tests/busted_setup.lua`**

Write exactly (ported from claudecode.nvim, module path changed):

```lua
-- Test setup for busted. Loads vim mock if running outside Neovim.
if not _G.vim then
  _G.vim = require("mocks.vim")
end
_G.vim = _G.vim or {}
_G.assert = require("luassert")

_G.expect = function(value)
  return {
    to_be = function(expected) assert.are.equal(expected, value) end,
    to_be_nil = function() assert.is_nil(value) end,
    to_be_true = function() assert.is_true(value) end,
    to_be_false = function() assert.is_false(value) end,
    to_be_table = function() assert.is_table(value) end,
    to_be_string = function() assert.is_string(value) end,
    to_be_function = function() assert.is_function(value) end,
    to_be_boolean = function() assert.is_boolean(value) end,
    to_be_at_least = function(expected) assert.is_true(value >= expected) end,
    to_have_key = function(key)
      assert.is_table(value)
      assert.not_nil(value[key])
    end,
    not_to_be_nil = function() assert.is_not_nil(value) end,
    to_be_truthy = function() assert.is_truthy(value) end,
    to_match = function(pattern)
      assert.is_string(value)
      assert.is_true(
        string.find(value, pattern, 1, true) ~= nil,
        "Expected '" .. tostring(value) .. "' to match '" .. pattern .. "'"
      )
    end,
    not_to_match = function(pattern)
      assert.is_string(value)
      assert.is_true(
        string.find(value, pattern, 1, true) == nil,
        "Expected '" .. tostring(value) .. "' NOT to match '" .. pattern .. "'"
      )
    end,
    to_be_number = function() assert.is_number(value) end,
    to_equal = function(expected) assert.are.same(expected, value) end,
  }
end
```

- [ ] **Step 2: Replace `tests/mocks/vim.lua` with full port**

Read the full content of `claudecode.nvim/tests/mocks/vim.lua` (1029 lines), then write it to `tests/mocks/vim.lua` with these changes:
1. First line: change comment to `--- Mock implementation of the Neovim API for codex.nvim tests.`
2. Add `vim.uv` as alias for `vim.loop` at the end, just before `return vim`:

```lua
  -- vim.uv is the modern alias for vim.loop (Neovim 0.10+)
  uv = nil,  -- set below
```

And after the main table literal closes, before `return vim`:

```lua
vim.uv = vim.loop
return vim
```

3. Add `vim.system` stub inside the table (after the `loop` key):

```lua
  system = function(cmd, opts, on_exit)
    -- Stub: records the call for test assertions.
    vim._last_system = { cmd = cmd, opts = opts }
    local obj = {
      pid = 12345,
      wait = function(self, timeout) return { code = 0 } end,
      kill = function(self, signal) end,
    }
    if on_exit then
      on_exit({ code = 0, signal = 0, stdout = "", stderr = "" })
    end
    return obj
  end,
```

4. Add `vim.empty_dict` stub (used by rpc.lua):

```lua
  empty_dict = function() return {} end,
```

- [ ] **Step 3: Verify the mock loads without error**

Run: `LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" lua -e "local v = require('mocks.vim'); print('ok', type(v.loop))"`
Expected: `ok  table`

- [ ] **Step 4: Commit infrastructure**

```bash
git add tests/busted_setup.lua tests/mocks/vim.lua
git commit -m "test: port vim mock and busted setup from claudecode.nvim"
```

---

## Task 2: `transport/utils.lua`

**Files:**
- Create: `lua/codex/transport/utils.lua`
- Create: `tests/unit/transport_utils_spec.lua`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p lua/codex/transport
```

- [ ] **Step 2: Write failing tests first**

Create `tests/unit/transport_utils_spec.lua`:

```lua
require("busted_setup")

describe("transport.utils", function()
  local utils

  before_each(function()
    package.loaded["codex.transport.utils"] = nil
    utils = require("codex.transport.utils")
  end)

  describe("sha1", function()
    it("produces FIPS-180 vector for 'abc'", function()
      local hash = utils.sha1("abc")
      assert.is_not_nil(hash)
      local hex = {}
      for i = 1, #hash do hex[i] = string.format("%02x", hash:byte(i)) end
      assert.are.equal("a9993e364706816aba3e25717850c26c9cd0d89d", table.concat(hex))
    end)

    it("returns nil for non-string input", function()
      assert.is_nil(utils.sha1(nil))
      assert.is_nil(utils.sha1(42))
    end)

    it("handles empty string", function()
      local hash = utils.sha1("")
      assert.is_not_nil(hash)
      local hex = {}
      for i = 1, #hash do hex[i] = string.format("%02x", hash:byte(i)) end
      assert.are.equal("da39a3ee5e6b4b0d3255bfef95601890afd80709", table.concat(hex))
    end)
  end)

  describe("base64_encode", function()
    it("encodes empty string to empty string", function()
      assert.are.equal("", utils.base64_encode(""))
    end)

    it("encodes 'Man' to 'TWFu'", function()
      assert.are.equal("TWFu", utils.base64_encode("Man"))
    end)

    it("encodes single byte with padding", function()
      assert.are.equal("AA==", utils.base64_encode("\x00"))
    end)
  end)

  describe("base64_decode", function()
    it("roundtrips all byte values 0x00–0xFF", function()
      local data = ""
      for i = 0, 255 do data = data .. string.char(i) end
      local encoded = utils.base64_encode(data)
      local decoded = utils.base64_decode(encoded)
      assert.are.equal(data, decoded)
    end)

    it("decodes 'TWFu' to 'Man'", function()
      assert.are.equal("Man", utils.base64_decode("TWFu"))
    end)
  end)

  describe("generate_websocket_key", function()
    it("returns a 24-character base64 string (16 random bytes padded)", function()
      local key = utils.generate_websocket_key()
      assert.are.equal(24, #key)
    end)

    it("returns different keys on consecutive calls", function()
      -- seeded differently each call via math.random
      local keys = {}
      for _ = 1, 5 do keys[#keys + 1] = utils.generate_websocket_key() end
      local unique = {}
      for _, k in ipairs(keys) do unique[k] = true end
      assert.is_true(#keys > 1)  -- at least some calls
    end)
  end)

  describe("generate_accept_key", function()
    it("produces RFC 6455 section-1.3 test vector", function()
      local key = "dGhlIHNhbXBsZSBub25jZQ=="
      local accept = utils.generate_accept_key(key)
      assert.are.equal("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept)
    end)
  end)

  describe("uint16/uint64 helpers", function()
    it("uint16 roundtrips", function()
      assert.are.equal(0x1234, utils.bytes_to_uint16(utils.uint16_to_bytes(0x1234)))
    end)

    it("bytes_to_uint16 reads big-endian", function()
      assert.are.equal(256, utils.bytes_to_uint16("\x01\x00"))
    end)
  end)
end)
```

- [ ] **Step 3: Run to confirm failure**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_utils_spec.lua
```
Expected: error like `module 'codex.transport.utils' not found`

- [ ] **Step 4: Write `lua/codex/transport/utils.lua`**

Copy the **full content** of `claudecode.nvim/lua/claudecode/server/utils.lua` into `lua/codex/transport/utils.lua`, then make these edits:

1. Replace the first line `---@brief Utility functions for WebSocket server implementation` with:
   `---@brief Utility functions for WebSocket transport (client side)`

2. Remove the functions `parse_http_headers` and `shuffle_array` (not needed by client).

3. Keep everything else verbatim: all bit-op helpers, `sha1`, `base64_encode`, `base64_decode`, `generate_websocket_key`, `generate_accept_key`, `uint16_to_bytes`, `uint64_to_bytes`, `bytes_to_uint16`, `bytes_to_uint64`, `apply_mask`, `is_valid_utf8`, `xor_table`.

The module path stays `local M = {}` / `return M` — no other changes needed.

- [ ] **Step 5: Run tests and confirm they pass**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_utils_spec.lua
```
Expected: all green, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lua/codex/transport/utils.lua tests/unit/transport_utils_spec.lua
git commit -m "feat(transport): add utils.lua (SHA-1, Base64, WS key helpers)"
```

---

## Task 3: `transport/frame.lua`

**Files:**
- Create: `lua/codex/transport/frame.lua`
- Create: `tests/unit/transport_frame_spec.lua`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/transport_frame_spec.lua`:

```lua
require("busted_setup")

describe("transport.frame", function()
  local frame

  before_each(function()
    package.loaded["codex.transport.utils"] = nil
    package.loaded["codex.transport.frame"] = nil
    frame = require("codex.transport.frame")
  end)

  local function encode_decode(text, masked)
    local encoded = frame.create_frame(frame.OPCODE.TEXT, text, true, masked or false)
    local f, consumed = frame.parse_frame(encoded)
    return f, consumed, #encoded
  end

  it("roundtrips empty payload (0 bytes)", function()
    local f, consumed, total = encode_decode("")
    assert.is_not_nil(f)
    assert.are.equal(0, f.payload_length)
    assert.are.equal("", f.payload)
    assert.are.equal(total, consumed)
  end)

  it("roundtrips 125-byte payload (7-bit length field)", function()
    local text = string.rep("a", 125)
    local f = encode_decode(text)
    assert.is_not_nil(f)
    assert.are.equal(125, f.payload_length)
    assert.are.equal(text, f.payload)
  end)

  it("roundtrips 126-byte payload (16-bit extended length)", function()
    local text = string.rep("b", 126)
    local f = encode_decode(text)
    assert.is_not_nil(f)
    assert.are.equal(126, f.payload_length)
    assert.are.equal(text, f.payload)
  end)

  it("roundtrips 65535-byte payload (upper 16-bit)", function()
    local text = string.rep("c", 65535)
    local f = encode_decode(text)
    assert.is_not_nil(f)
    assert.are.equal(65535, f.payload_length)
    assert.are.equal(text, f.payload)
  end)

  it("roundtrips 65536-byte payload (64-bit extended length)", function()
    local text = string.rep("d", 65536)
    local f = encode_decode(text)
    assert.is_not_nil(f)
    assert.are.equal(65536, f.payload_length)
    assert.are.equal(text, f.payload)
  end)

  it("roundtrips masked client-to-server frame", function()
    local text = "hello codex"
    local f = encode_decode(text, true)
    assert.is_not_nil(f)
    -- parse_frame unmasks, so payload should equal original
    assert.are.equal(text, f.payload)
  end)

  it("PING frame has correct opcode and empty payload", function()
    local data = frame.create_ping_frame()
    local f = frame.parse_frame(data)
    assert.is_not_nil(f)
    assert.are.equal(frame.OPCODE.PING, f.opcode)
    assert.are.equal("", f.payload)
  end)

  it("PONG frame echoes ping data", function()
    local data = frame.create_pong_frame("echo-me")
    local f = frame.parse_frame(data)
    assert.is_not_nil(f)
    assert.are.equal(frame.OPCODE.PONG, f.opcode)
    assert.are.equal("echo-me", f.payload)
  end)

  it("CLOSE frame uses code 1000 by default", function()
    local data = frame.create_close_frame()
    local f = frame.parse_frame(data)
    assert.is_not_nil(f)
    assert.are.equal(frame.OPCODE.CLOSE, f.opcode)
    -- first 2 bytes of payload are the close code big-endian
    assert.are.equal(1000, f.payload:byte(1) * 256 + f.payload:byte(2))
  end)

  it("parse_frame returns nil for incomplete data (1 byte)", function()
    local f, consumed = frame.parse_frame("\x81")
    assert.is_nil(f)
    assert.are.equal(0, consumed)
  end)

  it("parse_frame returns nil for empty string", function()
    local f, consumed = frame.parse_frame("")
    assert.is_nil(f)
    assert.are.equal(0, consumed)
  end)

  it("fin flag is set by default", function()
    local data = frame.create_text_frame("test")
    local f = frame.parse_frame(data)
    assert.is_not_nil(f)
    assert.is_true(f.fin)
  end)
end)
```

- [ ] **Step 2: Run to confirm failure**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_frame_spec.lua
```
Expected: `module 'codex.transport.frame' not found`

- [ ] **Step 3: Write `lua/codex/transport/frame.lua`**

Copy the **full content** of `claudecode.nvim/lua/claudecode/server/frame.lua` into `lua/codex/transport/frame.lua`, then make exactly **one change**:

Replace:
```lua
local utils = require("claudecode.server.utils")
```
With:
```lua
local utils = require("codex.transport.utils")
```

Everything else stays verbatim.

- [ ] **Step 4: Run tests and confirm they pass**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_frame_spec.lua
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/transport/frame.lua tests/unit/transport_frame_spec.lua
git commit -m "feat(transport): add frame.lua (RFC 6455 encode/decode)"
```

---

## Task 4: `transport/handshake.lua`

**Files:**
- Create: `lua/codex/transport/handshake.lua`
- Create: `tests/unit/transport_handshake_spec.lua`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/transport_handshake_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run to confirm failure**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_handshake_spec.lua
```
Expected: `module 'codex.transport.handshake' not found`

- [ ] **Step 3: Write `lua/codex/transport/handshake.lua`**

```lua
local utils = require("codex.transport.utils")
local M = {}

---Parse a ws:// URL into host, port, path.
---@param url string
---@return table|nil parsed, string|nil error
function M.parse_url(url)
  local host, port, path = url:match("^ws://([^:/]+):(%d+)(/?.*)")
  if not host then
    return nil, "Only ws://host:port[/path] URLs are supported: " .. tostring(url)
  end
  if path == "" then path = "/" end
  return { host = host, port = tonumber(port), path = path }
end

---Build an HTTP/1.1 WebSocket upgrade request string.
---@param host string
---@param port number
---@param path string
---@param key string Base64-encoded 16-byte nonce
---@return string
function M.build_request(host, port, path, key)
  return table.concat({
    "GET " .. path .. " HTTP/1.1",
    "Host: " .. host .. ":" .. tostring(port),
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: " .. key,
    "Sec-WebSocket-Version: 13",
    "",
    "",
  }, "\r\n")
end

---Parse the server's HTTP upgrade response.
---@param response string The full HTTP response headers (including trailing \r\n\r\n)
---@return boolean ok, string accept_key_or_error
function M.parse_response(response)
  local status = response:match("^(HTTP/%d+%.%d+ %d+ [^\r\n]*)")
  if not status then
    return false, "Invalid HTTP response"
  end
  if not status:find(" 101 ", 1, true) then
    return false, "Expected 101 Switching Protocols, got: " .. status
  end
  -- Extract Sec-WebSocket-Accept (case-insensitive header name)
  local accept = response:match("[Ss]ec%-[Ww]eb[Ss]ocket%-[Aa]ccept:%s*([^\r\n]+)")
  return true, accept and (accept:gsub("%s+$", "")) or nil
end

---Validate the server's Sec-WebSocket-Accept against our client key.
---@param client_key string The key we sent in the upgrade request
---@param server_accept string The value the server returned
---@return boolean
function M.validate_accept(client_key, server_accept)
  local expected = utils.generate_accept_key(client_key)
  if not expected then return false end
  return expected == server_accept
end

return M
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_handshake_spec.lua
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/transport/handshake.lua tests/unit/transport_handshake_spec.lua
git commit -m "feat(transport): add handshake.lua (HTTP upgrade, URL parser)"
```

---

## Task 5: `transport/tcp.lua`

**Files:**
- Create: `lua/codex/transport/tcp.lua`

No dedicated unit test needed — tcp.lua is a thin vim.loop wrapper. It is exercised by the session tests in Task 6. A brief smoke test is included at the end of this task to confirm it loads without error under the mock.

- [ ] **Step 1: Write `lua/codex/transport/tcp.lua`**

```lua
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
```

- [ ] **Step 2: Confirm it loads under the mock**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" \
  lua -e "require('busted_setup'); local tcp = require('codex.transport.tcp'); print('loaded', type(tcp.new_connection))"
```
Expected: `loaded  function`

- [ ] **Step 3: Commit**

```bash
git add lua/codex/transport/tcp.lua
git commit -m "feat(transport): add tcp.lua (vim.loop TCP client factory)"
```

---

## Task 6: `transport/session.lua`

**Files:**
- Create: `lua/codex/transport/session.lua`
- Create: `tests/unit/transport_session_spec.lua`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/transport_session_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run to confirm failure**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_session_spec.lua
```
Expected: `module 'codex.transport.session' not found`

- [ ] **Step 3: Write `lua/codex/transport/session.lua`**

```lua
local tcp_mod = require("codex.transport.tcp")
local handshake = require("codex.transport.handshake")
local frame = require("codex.transport.frame")
local utils = require("codex.transport.utils")

local M = {}
local Session = {}
Session.__index = Session

local PING_INTERVAL_MS = 30000

---Create a new session (not yet connected).
---@param url string  ws://host:port[/path]
---@param callbacks table|nil  { on_open, on_message, on_close, on_error }
---@return Session|nil session, string|nil error
function M.new(url, callbacks)
  local parsed, err = handshake.parse_url(url)
  if not parsed then
    return nil, err
  end
  return setmetatable({
    url = url,
    parsed = parsed,
    callbacks = callbacks or {},
    state = "idle",
    buffer = "",
    handshake_buffer = "",
    ws_key = nil,
    conn = nil,
    ping_timer = nil,
  }, Session)
end

---Connect to the server. Transitions idle/closed → connecting.
function Session:connect()
  if self.state ~= "idle" and self.state ~= "closed" then return end
  self.state = "connecting"
  self.ws_key = utils.generate_websocket_key()

  self.conn = tcp_mod.new_connection(self.parsed.host, self.parsed.port, {
    on_connect = function()
      self.state = "handshaking"
      self.handshake_buffer = ""
      local req = handshake.build_request(
        self.parsed.host, self.parsed.port, self.parsed.path, self.ws_key
      )
      self.conn:write(req)
    end,
    on_data = function(data) self:_on_data(data) end,
    on_close = function() self:_on_disconnect() end,
    on_error = function(e) self:_on_error(e) end,
  })
end

---Send a text message. Only valid in open state.
---@param text string
---@return boolean ok, string|nil error
function Session:send(text)
  if self.state ~= "open" then
    return false, "session not open (state=" .. self.state .. ")"
  end
  -- client→server frames must be masked per RFC 6455
  local f = frame.create_frame(frame.OPCODE.TEXT, text, true, true)
  self.conn:write(f)
  return true
end

---Initiate a clean close handshake.
function Session:close()
  if self.state ~= "open" then return end
  self.state = "closing"
  self:_stop_heartbeat()
  self.conn:write(frame.create_close_frame())
end

-- Internal: called with raw bytes from the TCP layer.
function Session:_on_data(data)
  if self.state == "handshaking" then
    self.handshake_buffer = self.handshake_buffer .. data
    local header_end = self.handshake_buffer:find("\r\n\r\n", 1, true)
    if not header_end then return end

    local response = self.handshake_buffer:sub(1, header_end + 3)
    local remaining = self.handshake_buffer:sub(header_end + 4)
    local ok, accept = handshake.parse_response(response)
    if not ok then
      self:_on_error("WebSocket handshake failed: " .. tostring(accept))
      return
    end

    self.state = "open"
    self.buffer = remaining
    self:_start_heartbeat()
    if self.callbacks.on_open then self.callbacks.on_open() end
    if #remaining > 0 then self:_process_frames() end

  elseif self.state == "open" or self.state == "closing" then
    self.buffer = self.buffer .. data
    self:_process_frames()
  end
end

function Session:_process_frames()
  while #self.buffer >= 2 do
    local f, consumed = frame.parse_frame(self.buffer)
    if not f then break end
    self.buffer = self.buffer:sub(consumed + 1)
    self:_handle_frame(f)
  end
end

function Session:_handle_frame(f)
  if f.opcode == frame.OPCODE.TEXT then
    if self.callbacks.on_message then
      self.callbacks.on_message(f.payload)
    end
  elseif f.opcode == frame.OPCODE.PING then
    -- respond to server PINGs immediately (client→server pong must also be masked)
    self.conn:write(frame.create_frame(frame.OPCODE.PONG, f.payload, true, true))
  elseif f.opcode == frame.OPCODE.PONG then
    -- heartbeat acknowledged; nothing to do
  elseif f.opcode == frame.OPCODE.CLOSE then
    self:_stop_heartbeat()
    -- echo close frame back, then close
    self.conn:write(frame.create_frame(frame.OPCODE.CLOSE, f.payload, true, true))
    self.conn:close()
    self.state = "closed"
    if self.callbacks.on_close then self.callbacks.on_close() end
  end
end

function Session:_start_heartbeat()
  local uv = vim.uv or vim.loop
  self.ping_timer = uv.new_timer()
  self.ping_timer:start(PING_INTERVAL_MS, PING_INTERVAL_MS, function()
    vim.schedule(function()
      if self.state == "open" then
        -- masked ping from client
        self.conn:write(frame.create_frame(frame.OPCODE.PING, "", true, true))
      end
    end)
  end)
end

function Session:_stop_heartbeat()
  if self.ping_timer then
    pcall(function()
      self.ping_timer:stop()
      self.ping_timer:close()
    end)
    self.ping_timer = nil
  end
end

function Session:_on_disconnect()
  self:_stop_heartbeat()
  self.state = "closed"
  if self.callbacks.on_close then self.callbacks.on_close() end
end

function Session:_on_error(err)
  self:_stop_heartbeat()
  if self.conn then
    pcall(function() self.conn:close() end)
  end
  self.state = "closed"
  if self.callbacks.on_error then self.callbacks.on_error(err) end
end

return M
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/transport_session_spec.lua
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/transport/session.lua tests/unit/transport_session_spec.lua
git commit -m "feat(transport): add session.lua (WS state machine + heartbeat)"
```

---

## Task 7: `transport/init.lua` (facade)

**Files:**
- Create: `lua/codex/transport/init.lua`

- [ ] **Step 1: Write `lua/codex/transport/init.lua`**

```lua
local session = require("codex.transport.session")

---@class Transport
---Facade over transport.session. Consumers require("codex.transport") and call M.new().
local M = {}

---Create a new WebSocket session (not yet connected).
---@param url string  ws://host:port[/path]
---@param callbacks table|nil  { on_open, on_message, on_close, on_error }
---@return Session|nil session, string|nil error
function M.new(url, callbacks)
  return session.new(url, callbacks)
end

return M
```

- [ ] **Step 2: Verify it loads and delegates**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" \
  lua -e "require('busted_setup'); local t = require('codex.transport'); print('ok', type(t.new))"
```
Expected: `ok  function`

- [ ] **Step 3: Commit**

```bash
git add lua/codex/transport/init.lua
git commit -m "feat(transport): add init.lua facade"
```

---

## Task 8: `rpc.lua`

**Files:**
- Create: `lua/codex/rpc.lua`
- Create: `tests/unit/rpc_spec.lua`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/rpc_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run to confirm failure**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/rpc_spec.lua
```
Expected: `module 'codex.rpc' not found`

- [ ] **Step 3: Write `lua/codex/rpc.lua`**

Port the stash's `lua/codex/rpc.lua` verbatim, then make one change: replace:
```lua
local websocket = require("codex.websocket")
```
with:
```lua
local transport = require("codex.transport")
```

And in `M.connect`, replace:
```lua
local client, err = websocket.connect(url, {
    on_open = function()
        if rpc.on_open then
            rpc.on_open(rpc)
        end
    end,
    on_close = ...
    on_error = ...
    on_message = ...
})

if not client then
    return nil, err
end

rpc.client = client
return rpc, nil
```

with:

```lua
local session, err = transport.new(url, {
    on_open = function()
        if rpc.on_open then
            rpc.on_open(rpc)
        end
    end,
    on_close = function()
        rpc:_fail_all("WebSocket closed")
        if rpc.on_close then
            rpc.on_close()
        end
    end,
    on_error = function(message)
        if rpc.on_error then
            rpc.on_error(message)
        end
    end,
    on_message = function(message)
        rpc:_handle_message(message)
    end,
})

if not session then
    return nil, err
end

session:connect()
rpc.client = session
return rpc, nil
```

Also update `Rpc:_send` to use `self.client:send(encoded)` (already correct since session has `:send()`).

And update `Rpc:close`:
```lua
function Rpc:close()
    self:_fail_all("Connection closed")
    if self.client then
        self.client:close()
    end
end
```

**Note:** The on_notification in `connect` opts maps to `on_message` in the transport callbacks — this is already wired correctly since `on_message = function(message) rpc:_handle_message(message) end` and `_handle_message` dispatches notifications internally.

The full `lua/codex/rpc.lua` (keeping all stash logic, only changing the transport layer):

```lua
local transport = require("codex.transport")

local M = {}
local Rpc = {}
Rpc.__index = Rpc

function M.connect(url, opts)
  opts = opts or {}
  local rpc = setmetatable({
    url = url,
    next_id = 1,
    pending = {},
    request_timeout_ms = opts.request_timeout_ms or 120000,
    on_open = opts.on_open,
    on_close = opts.on_close,
    on_error = opts.on_error,
    on_notification = opts.on_notification,
    on_request = opts.on_request,
  }, Rpc)

  local session, err = transport.new(url, {
    on_open = function()
      if rpc.on_open then rpc.on_open(rpc) end
    end,
    on_close = function()
      rpc:_fail_all("WebSocket closed")
      if rpc.on_close then rpc.on_close() end
    end,
    on_error = function(message)
      if rpc.on_error then rpc.on_error(message) end
    end,
    on_message = function(message)
      rpc:_handle_message(message)
    end,
  })

  if not session then
    return nil, err
  end

  session:connect()
  rpc.client = session
  return rpc, nil
end

function Rpc:_send(payload)
  local encoded = vim.json.encode(payload)
  return self.client:send(encoded)
end

function Rpc:_next_request_id()
  local id = self.next_id
  self.next_id = self.next_id + 1
  return id
end

function Rpc:request(method, params, callback, timeout_ms)
  local id = self:_next_request_id()
  local timer = (vim.uv or vim.loop).new_timer()

  timer:start(timeout_ms or self.request_timeout_ms, 0, function()
    vim.schedule(function()
      local pending = self.pending[id]
      if not pending then return end
      self.pending[id] = nil
      timer:stop()
      timer:close()
      if pending.callback then
        pending.callback(nil, { message = "Request timed out: " .. method })
      end
    end)
  end)

  self.pending[id] = { method = method, callback = callback, timer = timer }

  local ok, err = self:_send({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or vim.empty_dict(),
  })

  if not ok then
    self.pending[id] = nil
    timer:stop()
    timer:close()
    if callback then callback(nil, { message = err or "Failed to send request" }) end
  end

  return id
end

function Rpc:notify(method, params)
  return self:_send({
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  })
end

function Rpc:respond(id, result, error_data)
  local response = { jsonrpc = "2.0", id = id }
  if error_data then
    response.error = error_data
  else
    response.result = result or vim.empty_dict()
  end
  return self:_send(response)
end

function Rpc:_handle_message(message)
  local ok, decoded = pcall(vim.json.decode, message)
  if not ok or type(decoded) ~= "table" then
    if self.on_error then self.on_error("Invalid JSON-RPC message") end
    return
  end

  -- Response to our request
  if decoded.id and (decoded.result ~= nil or decoded.error ~= nil) then
    local pending = self.pending[decoded.id]
    if not pending then return end
    self.pending[decoded.id] = nil
    if pending.timer then pending.timer:stop(); pending.timer:close() end
    if pending.callback then pending.callback(decoded.result, decoded.error) end
    return
  end

  -- Server-initiated request (has id + method)
  if decoded.id and decoded.method then
    if self.on_request then
      self.on_request(decoded.method, decoded.params or {}, function(result, error_data)
        self:respond(decoded.id, result, error_data)
      end)
    else
      self:respond(decoded.id, nil, { code = -32601, message = "Method not found" })
    end
    return
  end

  -- Notification (method, no id)
  if decoded.method and self.on_notification then
    self.on_notification(decoded.method, decoded.params or {})
  end
end

function Rpc:_fail_all(message)
  for id, pending in pairs(self.pending) do
    self.pending[id] = nil
    if pending.timer then pending.timer:stop(); pending.timer:close() end
    if pending.callback then pending.callback(nil, { message = message }) end
  end
end

function Rpc:close()
  self:_fail_all("Connection closed")
  if self.client then self.client:close() end
end

return M
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" busted tests/unit/rpc_spec.lua
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/rpc.lua tests/unit/rpc_spec.lua
git commit -m "feat: add rpc.lua (JSON-RPC 2.0 over transport)"
```

---

## Task 9: `app_server.lua`

**Files:**
- Create: `lua/codex/app_server.lua`

No unit test for this task — it supervises a real subprocess and is best tested by the Phase 2 integration smoke test (`:Codex` panel brings up the server). We port the stash prototype here and wire it to rpc.lua.

- [ ] **Step 1: Extract the stash prototype for reference (do not commit)**

```bash
git show "stash@{0}^3:lua/codex/app_server.lua" > /tmp/app_server_ref.lua
```

Read `/tmp/app_server_ref.lua`. The key pieces to port:
- `pick_port()` — random port in configured range
- `start_process()` — `vim.fn.jobstart` with the subprocess command
- `connect_when_ready(deadline_ms)` — poll-connect with backoff
- `initialize(rpc, callback)` — sends `initialize` + `initialized` notification
- `M.ensure(callback)` — the main public API
- `M.run_prompt(prompt, opts)` — submits a prompt to a thread
- `M.stop()` — kills the subprocess

- [ ] **Step 2: Write `lua/codex/app_server.lua`**

Port the stash prototype verbatim, making these changes:

1. Replace `local context = require("codex.context")` with a local `cwd()` helper:
```lua
local function cwd()
  return vim.fn.getcwd()
end
```

2. Replace `local rpc_client = require("codex.rpc")` with `local rpc_client = require("codex.rpc")` (same, keep as-is).

3. Replace `local config = require("codex.config")` dependency: for Phase 1 use a hardcoded config with sensible defaults. Add at the top:
```lua
local default_opts = {
  codex_cmd = "codex",
  app_server = {
    listen_host = "127.0.0.1",
    port_range = { min = 10000, max = 65535 },
    startup_timeout_ms = 5000,
    request_timeout_ms = 120000,
    approval_policy = "never",
  },
}
```

And replace all `config.options.*` references with `default_opts.*`. Replace `config.options.app_server` with `default_opts.app_server`. Replace `config.options.codex_cmd` with `default_opts.codex_cmd`. Replace `config.options.chat.sandbox` with `"workspace-write"`.

4. Replace `context.cwd()` with `cwd()`.

5. Keep the `M._handle_notification`, `M._event_from_notification`, `thread_id_from_result`, `start_thread`, `event_from_notification` functions verbatim from the stash.

6. Keep `M.run_prompt`, `M.ensure`, `M.stop`, `M.url` verbatim.

7. Add a `VimLeavePre` autocmd at the end to ensure cleanup:
```lua
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("codex_app_server_cleanup", { clear = true }),
  callback = function() M.stop() end,
})
```

- [ ] **Step 3: Verify it loads without error under the mock**

```bash
LUA_PATH="./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua" \
  lua -e "require('busted_setup'); local a = require('codex.app_server'); print('ok', type(a.ensure))"
```
Expected: `ok  function`

- [ ] **Step 4: Run full test suite**

```bash
make test
```
Expected: all unit tests pass, no failures.

- [ ] **Step 5: Commit**

```bash
git add lua/codex/app_server.lua
git commit -m "feat: add app_server.lua (codex app-server subprocess supervisor)"
```

---

## Task 10: Phase 1 closeout

- [ ] **Step 1: Run full suite one final time**

```bash
make test
```
Expected: 0 failures.

- [ ] **Step 2: Check file structure**

```bash
ls lua/codex/transport/
ls lua/codex/
ls tests/unit/
```

Expected:
```
transport/: frame.lua  handshake.lua  init.lua  session.lua  tcp.lua  utils.lua
lua/codex/:  app_server.lua  init.lua  rpc.lua  transport/
tests/unit/: rpc_spec.lua  transport_frame_spec.lua  transport_handshake_spec.lua
             transport_session_spec.lua  transport_utils_spec.lua
```

- [ ] **Step 3: Tag phase-1-complete**

```bash
git tag -a phase-1-complete -m "Transport layer + RPC + app_server supervisor"
```

- [ ] **Step 4: Verify `require('codex.app_server')` loads cleanly in Neovim**

Run in one Neovim command: `:lua require('codex.app_server'); print('ok')`
Expected: no error (the `VimLeavePre` autocmd also registers without error).

---

## Self-Review

**Spec coverage check:**

| Plan requirement | Task |
|-----------------|------|
| `transport/utils.lua` — SHA-1 + Base64 | Task 2 |
| `transport/frame.lua` — RFC 6455 codec | Task 3 |
| `transport/handshake.lua` — client WS upgrade | Task 4 |
| `transport/tcp.lua` — vim.loop TCP client | Task 5 |
| `transport/session.lua` — state machine + heartbeat | Task 6 |
| `transport/init.lua` — facade | Task 7 |
| `lua/codex/rpc.lua` — JSON-RPC 2.0 | Task 8 |
| `lua/codex/app_server.lua` — supervisor | Task 9 |
| Port vim mock | Task 1 |
| Tests: SHA-1 vector + Base64 roundtrip | Task 2 |
| Tests: frame length boundaries (0, 125, 126, 65535, 65536) | Task 3 |
| Tests: handshake build/parse/validate | Task 4 |
| Tests: session state machine | Task 6 |
| Tests: RPC request/notify/respond/notification | Task 8 |
| `make test` exits 0 | Task 10 |

**Placeholder scan:** None. Every step contains the actual command, code, or file content.

**Type/name consistency:**
- `transport.new(url, callbacks)` returns a Session object — used in `rpc.lua` as `session:connect()`, `session:send()`, `session:close()` ✓
- `session._callbacks.on_message` is the callback name used in tests ✓
- `frame.create_frame(opcode, payload, fin, masked)` signature used consistently ✓
- `rpc:request(method, params, callback, timeout_ms)` signature consistent in tests ✓

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-06-phase-1-transport.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, two-stage review, fastest iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
