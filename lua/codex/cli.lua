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

local function setup_terminal_keymaps(bufnr)
    local opts = { buffer = bufnr, silent = true }

    vim.keymap.set("t", "jk", [[<C-\><C-n>]], vim.tbl_extend("force", opts, {
        desc = "Leave Codex terminal input mode",
    }))
    vim.keymap.set("t", "<C-q>", [[<C-\><C-n><Cmd>lua require("codex.cli").toggle_tui()<CR>]], vim.tbl_extend("force", opts, {
        desc = "Close Codex terminal window",
    }))
    vim.keymap.set("n", "q", M.toggle_tui, vim.tbl_extend("force", opts, {
        desc = "Close Codex terminal window",
    }))
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
    local args = {
        "exec",
        "--json",
        "--color",
        "never",
        "-C",
        cwd,
        "--sandbox",
        opts.sandbox or config.options.edit.sandbox.manual,
        "-",
    }

    if output_file then
        vim.list_extend(args, { "--output-last-message", output_file })
    end

    if opts.model then
        vim.list_extend(args, { "--model", opts.model })
    end
    if opts.profile then
        vim.list_extend(args, { "--profile", opts.profile })
    end

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
        vim.cmd("botright split")
        vim.cmd("resize " .. math.floor(vim.o.lines * 0.35))
        vim.api.nvim_win_set_buf(0, state.bufnr)
        state.winid = vim.api.nvim_get_current_win()
        setup_terminal_keymaps(state.bufnr)
        vim.cmd("startinsert")
        return
    end
    state.bufnr = nil
    state.winid = nil

    args = args or {}
    local cwd = context.cwd()
    local cmd = executable()
    local command_parts = { vim.fn.shellescape(cmd), "-C", vim.fn.shellescape(cwd) }

    if config.options.cli.no_alt_screen then
        command_parts[#command_parts + 1] = "--no-alt-screen"
    end

    for _, arg in ipairs(args) do
        command_parts[#command_parts + 1] = vim.fn.shellescape(arg)
    end

    vim.cmd("botright split")
    vim.cmd("resize " .. math.floor(vim.o.lines * 0.35))
    vim.cmd("terminal " .. table.concat(command_parts, " "))
    local bufnr = vim.api.nvim_get_current_buf()
    state.bufnr = bufnr
    state.winid = vim.api.nvim_get_current_win()
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
    if #args == 0 then
        args = { "--all" }
    end
    args = vim.list_extend({ "resume" }, args)
    M.open_tui(args)
end

return M
