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
