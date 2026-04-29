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

    it("passes quoted CLI command args as single args", function()
        local cli = require("codex.cli")
        local original_open_tui = cli.open_tui
        local captured
        cli.open_tui = function(args)
            captured = args
        end

        vim.cmd([[CodexCLI --profile "my profile"]])

        cli.open_tui = original_open_tui
        assert.are.same({ "--profile", "my profile" }, captured)
    end)
end)
