local config = require("codex.config")
local ui = require("codex.ui")

describe("codex.ui progress events", function()
    before_each(function()
        config.setup()
    end)

    it("filters lifecycle-only events", function()
        assert.is_nil(ui._event_summary({ type = "thread.started" }, "compact"))
        assert.is_nil(ui._event_summary({ type = "item.completed" }, "verbose"))
        assert.is_nil(ui._event_summary({
            type = "response.completed",
            message = "Final answer",
        }, "compact"))
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

    it("filters assistant text events that are rendered as final messages", function()
        assert.is_nil(ui._event_summary({
            type = "agent_message",
            message = "Final answer",
        }, "compact"))
        assert.is_nil(ui._event_summary({
            type = "response.output_text.delta",
            delta = "Final answer",
        }, "compact"))
        assert.is_nil(ui._event_summary({
            type = "response_item",
            item = {
                type = "message",
                role = "assistant",
                text = "Final answer",
            },
        }, "compact"))
    end)
end)

describe("codex.ui context summary", function()
    it("summarizes selected context with file and lines only", function()
        local long_line = string.rep("x", 320)
        local summary = ui._context_summary({
            path = "/tmp/example.lua",
            start_line = 10,
            end_line = 14,
            text = table.concat({
                "local one = 1",
                "local two = 2",
                long_line,
                "local four = 4",
                "local five = 5",
            }, "\n"),
        })

        assert.is_not_nil(summary:find("example.lua", 1, true))
        assert.is_not_nil(summary:find("Lines: 10-14 (5 lines)", 1, true))
        assert.is_not_nil(summary:find("Select Block", 1, true))
        assert.is_nil(summary:find(long_line, 1, true))
        assert.is_nil(summary:find("Preview:", 1, true))
        assert.is_nil(summary:find("## Context", 1, true))
    end)
end)

describe("codex.ui display lines", function()
    it("splits multiline strings before rendering", function()
        assert.are.same({ "one", "two", "three" }, ui._split_display_lines("one\ntwo\nthree"))
    end)

    it("can remove a streamed final message before rendering the final block", function()
        assert.is_false(ui._remove_trailing_block("missing"))
    end)

    it("deduplicates repeated event lines", function()
        assert.has_no.errors(function()
            ui._append_event("🛠 repeated command")
            ui._append_event("🛠 repeated command")
        end)
    end)
end)

describe("codex.ui chat sandbox", function()
    before_each(function()
        config.setup()
    end)

    it("uses workspace-write for chat prompts by default", function()
        local cli = require("codex.cli")
        local original_exec_json = cli.exec_json
        local captured
        cli.exec_json = function(_, opts)
            captured = opts
            if opts.on_exit then
                opts.on_exit(0, {}, {}, "")
            end
        end

        ui.ask("change this")

        cli.exec_json = original_exec_json
        assert.are.equal("workspace-write", captured.sandbox)
    end)
end)

describe("codex.ui diff handoff", function()
    it("opens diff review state when chat returns a patch", function()
        local diff = require("codex.diff")
        local original_diff = ui.diff
        local opened = false
        ui.diff = function()
            opened = true
        end

        local handled = ui._open_diff_from_message(table.concat({
            "summary",
            "```diff",
            "diff --git a/a.lua b/a.lua",
            "--- a/a.lua",
            "+++ b/a.lua",
            "@@ -1 +1 @@",
            "-old",
            "+new",
            "```",
        }, "\n"))

        ui.diff = original_diff
        assert.is_true(handled)
        assert.is_true(opened)
        assert.are.equal(1, #diff.get_state().files)
    end)
end)

describe("codex.ui diff view helpers", function()
    it("labels metadata-only files and maps file lines", function()
        local view = require("codex.ui.diff_view")
        local lines, line_map = view.lines({
            files = {
                {
                    header = {
                        "diff --git a/old.lua b/new.lua",
                        "rename from old.lua",
                        "rename to new.lua",
                    },
                    hunks = {},
                    accepted = true,
                },
            },
        })

        assert.is_not_nil(table.concat(lines, "\n"):find("metadata only", 1, true))
        local file_index, hunk_index = view.item_from_line(line_map, 5)
        assert.are.equal(1, file_index)
        assert.is_nil(hunk_index)
    end)
end)
