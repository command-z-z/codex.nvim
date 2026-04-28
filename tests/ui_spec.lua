local config = require("codex.config")
local ui = require("codex.ui")

describe("codex.ui progress events", function()
    before_each(function()
        config.setup()
    end)

    it("filters lifecycle-only events", function()
        assert.is_nil(ui._event_summary({ type = "thread.started" }, "compact"))
        assert.is_nil(ui._event_summary({ type = "item.completed" }, "verbose"))
    end)

    it("formats compact public progress text", function()
        assert.are.equal("⏳ Reading files", ui._event_summary({
            type = "turn.progress",
            message = "Reading files",
        }, "compact"))
    end)

    it("formats verbose public progress with event type", function()
        assert.are.equal("⏳ turn.progress: Reading files", ui._event_summary({
            type = "turn.progress",
            message = "Reading files",
        }, "verbose"))
    end)

    it("formats errors and reconnect notices", function()
        assert.are.equal("⚠ Reconnecting... 2/5", ui._event_summary({
            type = "error",
            message = "Reconnecting... 2/5",
        }, "compact"))
    end)

    it("formats tool and command events", function()
        assert.are.equal("🛠 rg TODO", ui._event_summary({
            type = "command.started",
            item = {
                command = "rg TODO",
            },
        }, "compact"))
    end)
end)
