local config = require("codex.config")
local args = require("codex.args")

local M = {}
local visual_context_keymap = nil

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
        require("codex.cli").open_tui(args.split(command.args))
    end, { nargs = "*" })

    vim.api.nvim_create_user_command("CodexCLIToggle", function(command)
        require("codex.cli").toggle_tui(args.split(command.args))
    end, { nargs = "*" })

    vim.api.nvim_create_user_command("CodexResume", function(command)
        require("codex.cli").resume(args.split(command.args))
    end, { nargs = "*" })

    if visual_context_keymap then
        pcall(vim.keymap.del, "v", visual_context_keymap)
        visual_context_keymap = nil
    end

    local keymaps = config.options.keymaps or {}
    if keymaps.visual_context then
        visual_context_keymap = keymaps.visual_context
        vim.keymap.set("v", visual_context_keymap, function()
            require("codex.ui").attach_selection()
        end, { silent = true, desc = "Attach selection to Codex chat" })
    end
end

return M
