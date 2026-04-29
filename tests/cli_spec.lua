local cli = require("codex.cli")
local config = require("codex.config")

describe("codex.cli", function()
    before_each(function()
        config.setup()
    end)

    it("builds tui args in the current cwd without shell escaping", function()
        local args = cli._build_tui_args({ "resume" }, "/tmp/project")

        assert.are.same({ "codex", "-C", "/tmp/project", "resume" }, args)
    end)

    it("does not add --all to resume by default", function()
        local captured
        local original_open_tui = cli.open_tui
        cli.open_tui = function(args)
            captured = args
        end

        cli.resume({})

        cli.open_tui = original_open_tui
        assert.are.same({ "resume" }, captured)
    end)

    it("skips git repo checks for exec json by default", function()
        local args = cli._build_exec_args({ sandbox = "read-only" }, "/tmp/project", "/tmp/out")

        assert.is_not_nil(vim.tbl_contains(args, "--skip-git-repo-check"))
        assert.are.equal("-", args[#args])
    end)

    it("can keep git repo checks for exec json when configured", function()
        config.setup({
            exec = {
                skip_git_repo_check = false,
            },
        })

        local args = cli._build_exec_args({ sandbox = "read-only" }, "/tmp/project", nil)

        assert.is_false(vim.tbl_contains(args, "--skip-git-repo-check"))
    end)

    it("does not create terminal-mode mappings by default", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)

        cli._setup_terminal_keymaps(bufnr)

        assert.are.equal("", vim.fn.maparg("jk", "t"))
        assert.are.equal("", vim.fn.maparg("<C-q>", "t"))
        assert.are_not.equal("", vim.fn.maparg("q", "n"))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("creates configured terminal-mode mappings only when requested", function()
        config.setup({
            cli = {
                keymaps = {
                    normal_close = "q",
                    terminal_close = "<C-q>",
                    terminal_escape = "jk",
                },
            },
        })
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)

        cli._setup_terminal_keymaps(bufnr)

        assert.are_not.equal("", vim.fn.maparg("jk", "t"))
        assert.are_not.equal("", vim.fn.maparg("<C-q>", "t"))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
