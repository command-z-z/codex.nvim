local M = {}

M.defaults = {
    codex_cmd = "codex",
    backend = "exec_json",
    ui = {
        layout = "right",
        width = 0.38,
        border = "rounded",
        progress = {
            mode = "compact",
        },
        keymaps = {
            focus_output = "<C-k>",
            focus_prompt = "<C-j>",
        },
    },
    keymaps = {
        visual_context = "<leader>aq",
    },
    exec = {
        skip_git_repo_check = true,
    },
    chat = {
        sandbox = "workspace-write",
    },
    cli = {
        terminal = "native",
        no_alt_screen = false,
        window = {
            layout = "center",
            width = 0.9,
            height = 0.85,
            border = "rounded",
        },
        keymaps = {
            normal_close = "q",
            terminal_close = false,
            terminal_escape = false,
        },
    },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    return M.options
end

return M
