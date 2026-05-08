-- tests/unit/logger_spec.lua
require("busted_setup")

describe("codex.logger", function()
  local logger
  local notify_calls

  before_each(function()
    package.loaded["codex.logger"] = nil
    notify_calls = {}
    vim.notify = function(msg, level, opts)
      table.insert(notify_calls, { msg = msg, level = level, opts = opts })
    end
    logger = require("codex.logger")
  end)

  -- ── set_level ──────────────────────────────────────────────────
  describe("set_level()", function()
    it("accepts numeric level", function()
      logger.set_level(vim.log.levels.WARN)
      assert.equals(vim.log.levels.WARN, logger.level)
    end)

    it("accepts string 'warn'", function()
      logger.set_level("warn")
      assert.equals(vim.log.levels.WARN, logger.level)
    end)

    it("accepts string 'error'", function()
      logger.set_level("error")
      assert.equals(vim.log.levels.ERROR, logger.level)
    end)

    it("accepts string 'info'", function()
      logger.set_level("info")
      assert.equals(vim.log.levels.INFO, logger.level)
    end)

    it("accepts string 'debug'", function()
      logger.set_level("debug")
      assert.equals(vim.log.levels.DEBUG, logger.level)
    end)

    it("accepts string 'trace'", function()
      logger.set_level("trace")
      assert.equals(0, logger.level)
    end)
  end)

  -- ── level filtering ────────────────────────────────────────────
  describe("level filtering", function()
    it("default level filters out debug messages", function()
      -- default level is WARN
      logger.debug("should be filtered")
      assert.equals(0, #notify_calls)
    end)

    it("default level shows warn messages", function()
      logger.warn("visible warning")
      assert.equals(1, #notify_calls)
    end)

    it("default level shows error messages", function()
      logger.error("visible error")
      assert.equals(1, #notify_calls)
    end)

    it("after set_level('debug'), debug messages are shown", function()
      logger.set_level("debug")
      logger.debug("now visible")
      assert.equals(1, #notify_calls)
    end)

    it("after set_level('error'), warn messages are filtered", function()
      logger.set_level("error")
      logger.warn("should be filtered")
      assert.equals(0, #notify_calls)
    end)

    it("after set_level('trace'), all messages are shown", function()
      logger.set_level("trace")
      logger.trace("trace msg")
      logger.debug("debug msg")
      logger.info("info msg")
      logger.warn("warn msg")
      logger.error("error msg")
      assert.equals(5, #notify_calls)
    end)
  end)

  -- ── message format ─────────────────────────────────────────────
  describe("message format", function()
    before_each(function()
      logger.set_level("trace")
    end)

    it("warn message contains the input string", function()
      logger.warn("test warning")
      assert.is_truthy(notify_calls[1].msg:find("test warning", 1, true))
    end)

    it("error message contains the input string", function()
      logger.error("test error")
      assert.is_truthy(notify_calls[1].msg:find("test error", 1, true))
    end)

    it("passes correct log level to vim.notify for warn", function()
      logger.warn("w")
      assert.equals(vim.log.levels.WARN, notify_calls[1].level)
    end)

    it("passes correct log level to vim.notify for error", function()
      logger.error("e")
      assert.equals(vim.log.levels.ERROR, notify_calls[1].level)
    end)

    it("passes correct log level to vim.notify for info", function()
      logger.info("i")
      assert.equals(vim.log.levels.INFO, notify_calls[1].level)
    end)

    it("passes title=codex.nvim in opts", function()
      logger.warn("w")
      assert.equals("codex.nvim", notify_calls[1].opts and notify_calls[1].opts.title)
    end)
  end)

  -- ── per-function level correctness ────────────────────────────
  describe("per-function levels", function()
    before_each(function()
      logger.set_level("trace")
    end)

    it("trace() passes level 0", function()
      logger.trace("t")
      assert.equals(0, notify_calls[1].level)
    end)

    it("debug() passes vim.log.levels.DEBUG", function()
      logger.debug("d")
      assert.equals(vim.log.levels.DEBUG, notify_calls[1].level)
    end)
  end)
end)
