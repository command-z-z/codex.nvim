local config = require("codex.config")
local context = require("codex.context")

local M = {}

local state = {
    bufnr = nil,
    winid = nil,
}

local function executable()
    return config.options.codex_cmd or "codex"
end

local function notify_error(message)
    vim.notify(message, vim.log.levels.ERROR, { title = "codex.nvim" })
end

local function terminal_running()
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
        return false
    end

    local job_id = vim.b[state.bufnr].terminal_job_id
    if not job_id then
        return false
    end

    return vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function resolve_size(value, total, min_value)
    if type(value) ~= "number" then
        return min_value
    end
    if value > 0 and value < 1 then
        return math.floor(total * value)
    end
    return math.floor(value)
end

local function float_config()
    local window = config.options.cli.window or {}
    local layout = window.layout == "right" and "right" or "center"
    local width = resolve_size(window.width or 0.9, vim.o.columns, 40)
    local height = resolve_size(window.height or 0.85, vim.o.lines, 10)

    local max_width = math.max(1, vim.o.columns - 4)
    local max_height = math.max(1, vim.o.lines - 4)
    width = math.min(math.max(20, width), max_width)
    height = math.min(math.max(6, height), max_height)

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    if layout == "right" then
        row = 1
        col = vim.o.columns - width - 2
    end

    return {
        relative = "editor",
        row = math.max(0, row),
        col = math.max(0, col),
        width = width,
        height = height,
        style = "minimal",
        border = window.border or config.options.ui.border or "rounded",
        title = window.title or " Codex CLI ",
        title_pos = "center",
    }
end

local function open_terminal_window(bufnr)
    local winid = vim.api.nvim_open_win(bufnr, true, float_config())
    state.winid = winid
    vim.wo[winid].number = false
    vim.wo[winid].relativenumber = false
    vim.wo[winid].signcolumn = "no"
    return winid
end

local function setup_terminal_keymaps(bufnr)
    local opts = { buffer = bufnr, silent = true }
    local keymaps = config.options.cli.keymaps or {}

    if keymaps.terminal_escape then
        vim.keymap.set("t", keymaps.terminal_escape, [[<C-\><C-n>]], vim.tbl_extend("force", opts, {
            desc = "Leave Codex terminal input mode",
        }))
    end
    if keymaps.terminal_close then
        vim.keymap.set("t", keymaps.terminal_close, [[<C-\><C-n><Cmd>lua require("codex.cli").toggle_tui()<CR>]], vim.tbl_extend("force", opts, {
            desc = "Hide Codex terminal window",
        }))
    end
    if keymaps.normal_close then
        vim.keymap.set("n", keymaps.normal_close, M.toggle_tui, vim.tbl_extend("force", opts, {
            desc = "Hide Codex terminal window",
        }))
    end
end

local function cleanup_terminal(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(winid) then
            pcall(vim.api.nvim_win_close, winid, true)
        end
    end

    if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    if state.bufnr == bufnr then
        state.bufnr = nil
        state.winid = nil
    end
end

local function setup_terminal_cleanup(bufnr)
    vim.bo[bufnr].buflisted = false
    vim.bo[bufnr].bufhidden = "hide"

    vim.api.nvim_create_autocmd("TermClose", {
        buffer = bufnr,
        once = true,
        callback = function()
            vim.schedule(function()
                cleanup_terminal(bufnr)
            end)
        end,
    })
end

local function build_tui_args(args, cwd)
    local command_args = { executable(), "-C", cwd }

    if config.options.cli.no_alt_screen then
        command_args[#command_args + 1] = "--no-alt-screen"
    end

    for _, arg in ipairs(args or {}) do
        command_args[#command_args + 1] = arg
    end

    return command_args
end

local function build_exec_args(opts, cwd, output_file)
    local args = {
        "exec",
        "--json",
        "--color",
        "never",
        "-C",
        cwd,
        "--sandbox",
        opts.sandbox or config.options.chat.sandbox,
    }

    local exec_options = config.options.exec or {}
    if exec_options.skip_git_repo_check ~= false then
        args[#args + 1] = "--skip-git-repo-check"
    end

    if output_file then
        vim.list_extend(args, { "--output-last-message", output_file })
    end

    if opts.model then
        vim.list_extend(args, { "--model", opts.model })
    end
    if opts.profile then
        vim.list_extend(args, { "--profile", opts.profile })
    end

    args[#args + 1] = "-"
    return args
end

function M.check()
    if vim.fn.executable(executable()) ~= 1 then
        notify_error("Codex CLI not found: " .. executable())
        return false
    end
    return true
end

function M.exec_json(prompt, opts)
    opts = opts or {}
    if not M.check() then
        return
    end

    local cwd = opts.cwd or context.cwd()
    local output_file = opts.output_last_message and vim.fn.tempname() or nil
    local args = build_exec_args(opts, cwd, output_file)

    local Job = require("plenary.job")
    local stdout = {}
    local stderr = {}

    Job:new({
        command = executable(),
        args = args,
        cwd = cwd,
        writer = prompt,
        on_stdout = function(_, line)
            if line and line ~= "" then
                stdout[#stdout + 1] = line
                local ok, event = pcall(vim.json.decode, line)
                if ok and opts.on_event then
                    vim.schedule(function()
                        opts.on_event(event)
                    end)
                end
            end
        end,
        on_stderr = function(_, line)
            if line and line ~= "" then
                stderr[#stderr + 1] = line
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                local final_message
                if output_file and vim.uv.fs_stat(output_file) then
                    final_message = table.concat(vim.fn.readfile(output_file), "\n")
                    vim.fn.delete(output_file)
                end
                if opts.on_exit then
                    opts.on_exit(code, stdout, stderr, final_message)
                end
            end)
        end,
    }):start()
end

function M.open_tui(args)
    if not M.check() then
        return
    end

    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
        vim.api.nvim_set_current_win(state.winid)
        vim.cmd("startinsert")
        return
    end

    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and terminal_running() then
        open_terminal_window(state.bufnr)
        setup_terminal_keymaps(state.bufnr)
        vim.cmd("startinsert")
        return
    end
    state.bufnr = nil
    state.winid = nil

    args = args or {}
    local cwd = context.cwd()
    local bufnr = vim.api.nvim_create_buf(false, false)
    state.bufnr = bufnr
    open_terminal_window(bufnr)
    vim.fn.termopen(build_tui_args(args, cwd), { cwd = cwd })
    setup_terminal_cleanup(bufnr)
    setup_terminal_keymaps(bufnr)
    vim.cmd("startinsert")
end

function M.toggle_tui(args)
    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
        vim.api.nvim_win_close(state.winid, true)
        state.winid = nil
        return
    end

    M.open_tui(args)
end

function M.resume(args)
    args = args or {}
    args = vim.list_extend({ "resume" }, args)
    M.open_tui(args)
end

function M._build_tui_args(args, cwd)
    return build_tui_args(args, cwd)
end

function M._build_exec_args(opts, cwd, output_file)
    return build_exec_args(opts or {}, cwd, output_file)
end

function M._setup_terminal_keymaps(bufnr)
    setup_terminal_keymaps(bufnr)
end

function M._float_config()
    return float_config()
end

return M
