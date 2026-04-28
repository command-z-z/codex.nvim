local config = require("codex.config")

local M = {}

local function split_args(args)
    if not args or args == "" then
        return {}
    end
    return vim.split(args, "%s+", { trimempty = true })
end

function M.setup(opts)
    config.setup(opts)

    vim.api.nvim_create_user_command("Codex", function()
        require("codex.ui").open()
    end, {})

    vim.api.nvim_create_user_command("CodexToggle", function()
        require("codex.ui").toggle()
    end, {})

    vim.api.nvim_create_user_command("CodexClose", function()
        require("codex.ui").close()
    end, {})

    vim.api.nvim_create_user_command("CodexAsk", function(command)
        local prompt = command.args
        if prompt == "" then
            vim.ui.input({ prompt = "Ask Codex: " }, function(value)
                if value and value ~= "" then
                    require("codex.ui").ask(value)
                end
            end)
            return
        end
        require("codex.ui").ask(prompt)
    end, { nargs = "*", range = true })

    vim.api.nvim_create_user_command("CodexEdit", function(command)
        local prompt = command.args
        if prompt == "" then
            vim.ui.input({ prompt = "Edit with Codex: " }, function(value)
                if value and value ~= "" then
                    require("codex.ui").edit(value)
                end
            end)
            return
        end
        require("codex.ui").edit(prompt)
    end, { nargs = "*", range = true })

    vim.api.nvim_create_user_command("CodexDiff", function()
        require("codex.ui").diff()
    end, {})

    vim.api.nvim_create_user_command("CodexDiffToggle", function()
        require("codex.ui").diff_toggle()
    end, {})

    vim.api.nvim_create_user_command("CodexApply", function()
        local ok, message = require("codex.diff").apply(require("codex.context").cwd())
        if ok then
            vim.cmd("checktime")
            vim.notify("Applied accepted Codex hunks", vim.log.levels.INFO, { title = "codex.nvim" })
        else
            vim.notify(message, vim.log.levels.ERROR, { title = "codex.nvim" })
        end
    end, {})

    vim.api.nvim_create_user_command("CodexCLI", function(command)
        require("codex.cli").open_tui(split_args(command.args))
    end, { nargs = "*" })

    vim.api.nvim_create_user_command("CodexCLIToggle", function(command)
        require("codex.cli").toggle_tui(split_args(command.args))
    end, { nargs = "*" })

    vim.api.nvim_create_user_command("CodexResume", function(command)
        require("codex.cli").resume(split_args(command.args))
    end, { nargs = "*" })
end

return M
