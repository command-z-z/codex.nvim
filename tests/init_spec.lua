local codex = require("codex")

describe("codex setup", function()
    before_each(function()
        codex.setup()
    end)

    it("does not create legacy ask or edit commands", function()
        assert.are.equal(0, vim.fn.exists(":CodexAsk"))
        assert.are.equal(0, vim.fn.exists(":CodexEdit"))
    end)

    it("creates the default visual context keymap", function()
        assert.are_not.equal("", vim.fn.maparg("<leader>aq", "v"))
    end)

    it("can disable the default visual context keymap", function()
        codex.setup({
            keymaps = {
                visual_context = false,
            },
        })

        assert.are.equal("", vim.fn.maparg("<leader>aq", "v"))
    end)
end)
