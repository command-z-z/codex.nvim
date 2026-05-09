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
      assert.are.equal("AA==", utils.base64_encode(string.char(0)))
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
      local keys = {}
      for _ = 1, 5 do keys[#keys + 1] = utils.generate_websocket_key() end
      local unique = {}
      for _, k in ipairs(keys) do unique[k] = true end
      local count = 0
      for _ in pairs(unique) do count = count + 1 end
      assert.is_true(count > 1)
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
      assert.are.equal(256, utils.bytes_to_uint16(string.char(1, 0)))
    end)
  end)

  describe("apply_mask", function()
    it("is involutory: double-apply restores original data", function()
      local data = "hello, websocket!"
      local mask = "\xAB\xCD\xEF\x01"
      local masked = utils.apply_mask(data, mask)
      local restored = utils.apply_mask(masked, mask)
      assert.are.equal(data, restored)
    end)

    it("XORs each byte with the corresponding mask byte (mod 4)", function()
      local data = string.char(0x00, 0x01, 0x02, 0x03)
      local mask = string.char(0xFF, 0xFF, 0xFF, 0xFF)
      local masked = utils.apply_mask(data, mask)
      assert.are.equal(string.char(0xFF, 0xFE, 0xFD, 0xFC), masked)
    end)
  end)

  describe("is_valid_utf8", function()
    it("accepts valid ASCII", function()
      assert.is_true(utils.is_valid_utf8("hello"))
    end)

    it("accepts valid 2-byte UTF-8 (U+00E9 é)", function()
      assert.is_true(utils.is_valid_utf8("\xC3\xA9"))
    end)

    it("accepts valid 3-byte UTF-8 (U+4E2D 中)", function()
      assert.is_true(utils.is_valid_utf8("\xE4\xB8\xAD"))
    end)

    it("accepts empty string", function()
      assert.is_true(utils.is_valid_utf8(""))
    end)

    it("accepts 4-byte UTF-8 sequence (U+1F600 😀)", function()
      assert.is_true(utils.is_valid_utf8("\xF0\x9F\x98\x80"))
    end)
  end)

  describe("uint64 helpers", function()
    it("uint64 roundtrips zero", function()
      assert.are.equal(0, utils.bytes_to_uint64(utils.uint64_to_bytes(0)))
    end)

    it("uint64 roundtrips large value", function()
      local val = 65537
      assert.are.equal(val, utils.bytes_to_uint64(utils.uint64_to_bytes(val)))
    end)
  end)
end)
