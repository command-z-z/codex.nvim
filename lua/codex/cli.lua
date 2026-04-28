local config = require("codex.config")
local context = require("codex.context")

local M = {}

local function executable()
    return config.options.codex_cmd or "codex"
end

local function notify_error(message)
    vim.notify(message, vim.log.levels.ERROR, { title = "codex.nvim" })
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
    vim.cmd("startinsert")
end

function M.resume(args)
    args = vim.list_extend({ "resume" }, args or {})
    M.open_tui(args)
end

return M
