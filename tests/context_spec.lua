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
end)
