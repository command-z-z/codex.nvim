local diff = require("codex.diff")
local context = require("codex.context")

describe("codex.diff", function()
    it("parses files and hunks", function()
        local patch = table.concat({
            "diff --git a/a.lua b/a.lua",
            "index 111..222 100644",
            "--- a/a.lua",
            "+++ b/a.lua",
            "@@ -1,2 +1,2 @@",
            " local a = 1",
            "-print(a)",
            "+print(a + 1)",
            "@@ -8,1 +8,1 @@",
            "-return a",
            "+return a + 1",
        }, "\n")

        local files = diff.parse(patch)
        assert.are.equal(1, #files)
        assert.are.equal(2, #files[1].hunks)
    end)

    it("renders accepted hunks only", function()
        diff.set_patch(table.concat({
            "diff --git a/a.lua b/a.lua",
            "index 111..222 100644",
            "--- a/a.lua",
            "+++ b/a.lua",
            "@@ -1 +1 @@",
            "-one",
            "+two",
            "@@ -3 +3 @@",
            "-three",
            "+four",
        }, "\n"))

        diff.reject(1, 2)
        local rendered = diff.render(true)
        assert.is_not_nil(rendered:find("@@ %-1 %+1 @@", 1, false))
        assert.is_nil(rendered:find("@@ %-3 %+3 @@", 1, false))
    end)

    it("extracts fenced diff", function()
        local patch = diff.extract_patch("summary\n```diff\ndiff --git a/x b/x\n--- a/x\n+++ b/x\n```\n")
        assert.are.equal("diff --git a/x b/x\n--- a/x\n+++ b/x", patch)
    end)

    it("does not include git diff in edit prompts", function()
        assert.is_nil(context.edit_prompt("change this"):find("<git_diff>", 1, true))
        assert.is_nil(context.auto_edit_prompt("change this"):find("<git_diff>", 1, true))
    end)
end)
