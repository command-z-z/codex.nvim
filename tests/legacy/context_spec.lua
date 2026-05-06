local context = require("codex.context")

describe("codex.context", function()
    it("uses explicit context when building prompts", function()
        local prompt = context.build_prompt("Explain this", {
            context = {
                path = "/tmp/example.lua",
                start_line = 2,
                end_line = 3,
                text = "local value = 1\nreturn value",
            },
            include_buffer = false,
            include_git_diff = false,
        })

        assert.is_not_nil(prompt:find("Explain this", 1, true))
        assert.is_not_nil(prompt:find('<context file="/tmp/example.lua" lines="2-3">', 1, true))
        assert.is_not_nil(prompt:find("local value = 1\nreturn value", 1, true))
    end)

    it("does not read old visual marks unless selection is requested", function()
        local original_selection = context.selection
        context.selection = function()
            return {
                path = "/tmp/stale.lua",
                start_line = 1,
                end_line = 1,
                text = "stale visual text",
            }
        end

        local prompt = context.build_prompt("Explain this", {
            include_buffer = false,
            include_git_diff = false,
        })

        context.selection = original_selection
        assert.is_nil(prompt:find("stale visual text", 1, true))
    end)

    it("can include selection explicitly", function()
        local original_selection = context.selection
        context.selection = function()
            return {
                path = "/tmp/selected.lua",
                start_line = 4,
                end_line = 4,
                text = "selected text",
            }
        end

        local prompt = context.build_prompt("Explain this", {
            include_selection = true,
            include_buffer = false,
            include_git_diff = false,
        })

        context.selection = original_selection
        assert.is_not_nil(prompt:find("selected text", 1, true))
    end)
end)
