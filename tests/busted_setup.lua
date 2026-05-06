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
