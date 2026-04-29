local diff = require("codex.diff")

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

    it("can mark files through the unified accepted state api", function()
        diff.set_patch(table.concat({
            "diff --git a/a.lua b/a.lua",
            "--- a/a.lua",
            "+++ b/a.lua",
            "@@ -1 +1 @@",
            "-one",
            "+two",
        }, "\n"))

        assert.is_true(diff.set_accepted(1, nil, false))
        assert.are.equal("", diff.render(true))
        assert.is_true(diff.set_accepted(1, nil, true))
        assert.is_not_nil(diff.render(true):find("diff --git a/a.lua b/a.lua", 1, true))
    end)

    it("renders metadata-only patches as whole-file changes", function()
        diff.set_patch(table.concat({
            "diff --git a/old.lua b/new.lua",
            "similarity index 100%",
            "rename from old.lua",
            "rename to new.lua",
        }, "\n"))

        local files = diff.get_state().files
        assert.are.equal(1, #files)
        assert.are.equal(0, #files[1].hunks)
        assert.is_not_nil(diff.render(true):find("rename to new.lua", 1, true))

        diff.reject(1)
        assert.are.equal("", diff.render(true))
    end)

    it("parses new and deleted file patches", function()
        local files = diff.parse(table.concat({
            "diff --git a/new.lua b/new.lua",
            "new file mode 100644",
            "index 0000000..1111111",
            "--- /dev/null",
            "+++ b/new.lua",
            "@@ -0,0 +1 @@",
            "+return 1",
            "diff --git a/old.lua b/old.lua",
            "deleted file mode 100644",
            "index 2222222..0000000",
            "--- a/old.lua",
            "+++ /dev/null",
            "@@ -1 +0,0 @@",
            "-return 0",
        }, "\n"))

        assert.are.equal(2, #files)
        assert.are.equal(1, #files[1].hunks)
        assert.are.equal(1, #files[2].hunks)
        assert.is_not_nil(files[1].header[2]:find("new file mode", 1, true))
        assert.is_not_nil(files[2].header[2]:find("deleted file mode", 1, true))
    end)

    it("marks binary patches as whole-file changes", function()
        diff.set_patch(table.concat({
            "diff --git a/image.png b/image.png",
            "index 111..222 100644",
            "GIT binary patch",
            "literal 0",
            "HcmV?d00001",
        }, "\n"))

        local files = diff.get_state().files
        assert.is_true(files[1].binary)
        assert.is_not_nil(diff.render(true):find("GIT binary patch", 1, true))
    end)

    it("extracts fenced diff", function()
        local patch = diff.extract_patch("summary\n```diff\ndiff --git a/x b/x\n--- a/x\n+++ b/x\n```\n")
        assert.are.equal("diff --git a/x b/x\n--- a/x\n+++ b/x", patch)
    end)
end)
