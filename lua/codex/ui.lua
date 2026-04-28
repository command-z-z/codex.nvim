local cli = require("codex.cli")
local config = require("codex.config")
local context = require("codex.context")
local diff = require("codex.diff")

local M = {}

local state = {
    popup = nil,
    input = nil,
    lines = {},
    cwd = nil,
}

local function require_nui()
    local ok_popup, Popup = pcall(require, "nui.popup")
    local ok_input, Input = pcall(require, "nui.input")
    local ok_event, event = pcall(require, "nui.utils.autocmd").event
    if not ok_popup or not ok_input or not ok_event then
        vim.notify("codex.nvim requires nui.nvim", vim.log.levels.ERROR, { title = "codex.nvim" })
        return nil
    end
    return Popup, Input, event
end

local function append(line)
    state.lines[#state.lines + 1] = line
    if state.popup and state.popup.bufnr and vim.api.nvim_buf_is_valid(state.popup.bufnr) then
        vim.bo[state.popup.bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(state.popup.bufnr, 0, -1, false, state.lines)
        vim.bo[state.popup.bufnr].modifiable = false
        vim.api.nvim_win_set_cursor(state.popup.winid, { #state.lines, 0 })
    end
end

local function append_block(title, text)
    append("")
    append("## " .. title)
    for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
        append(line)
    end
end

local function event_summary(event)
    if type(event) ~= "table" then
        return nil
    end
    if event.type then
        if event.message then
            return tostring(event.type) .. ": " .. tostring(event.message)
        end
        if event.delta then
            return tostring(event.delta)
        end
        if event.text then
            return tostring(event.text)
        end
        return "[" .. tostring(event.type) .. "]"
    end
    return nil
end

function M.open()
    if state.popup and state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
        vim.api.nvim_set_current_win(state.popup.winid)
        return
    end

    local Popup, Input, event = require_nui()
    if not Popup then
        return
    end

    local width = config.options.ui.width
    if width < 1 then
        width = math.floor(vim.o.columns * width)
    end

    local layout = config.options.ui.layout == "left" and "left" or "right"
    state.popup = Popup({
        enter = false,
        focusable = true,
        relative = "editor",
        position = layout,
        size = {
            width = width,
            height = vim.o.lines - 5,
        },
        border = {
            style = config.options.ui.border,
            text = {
                top = " codex.nvim ",
                top_align = "center",
            },
        },
        buf_options = {
            buftype = "nofile",
            filetype = "markdown",
            modifiable = false,
        },
    })

    state.input = Input({
        relative = "editor",
        position = {
            row = vim.o.lines - 3,
            col = layout == "right" and (vim.o.columns - width - 2) or 1,
        },
        size = {
            width = width,
            height = 1,
        },
        border = {
            style = config.options.ui.border,
            text = { top = " prompt " },
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
    }, {
        prompt = "> ",
        on_submit = function(value)
            if value and value ~= "" then
                M.ask(value)
            end
        end,
    })

    state.popup:mount()
    state.input:mount()
    state.popup:on(event.BufLeave, function() end, { once = false })

    if #state.lines == 0 then
        append("# Codex")
        append("Use :CodexAsk, :CodexEdit, or type a prompt below.")
    else
        append("")
    end
end

function M.close()
    if state.input then
        state.input:unmount()
        state.input = nil
    end
    if state.popup then
        state.popup:unmount()
        state.popup = nil
    end
end

local function run_prompt(prompt, opts)
    opts = opts or {}
    M.open()
    state.cwd = opts.cwd or context.cwd()
    append_block("You", prompt)
    append("")
    append("Codex is running...")

    cli.exec_json(prompt, {
        cwd = state.cwd,
        sandbox = opts.sandbox,
        output_last_message = true,
        on_event = function(event)
            local line = event_summary(event)
            if line and line ~= "" then
                append(line)
            end
        end,
        on_exit = function(code, _, stderr, final_message)
            if code ~= 0 then
                append_block("Error", table.concat(stderr or {}, "\n"))
                return
            end
            append_block("Codex", final_message or "")
            if opts.on_final then
                opts.on_final(final_message or "")
            end
        end,
    })
end

function M.ask(prompt)
    local full_prompt = context.build_prompt(prompt, { include_buffer = false, include_git_diff = false })
    run_prompt(full_prompt, {
        sandbox = "read-only",
    })
end

function M.edit(prompt)
    local mode = config.options.edit.mode
    local sandbox = config.options.edit.sandbox.manual
    if mode == "auto" then
        sandbox = config.options.edit.sandbox.auto
    end

    local full_prompt = mode == "auto" and context.auto_edit_prompt(prompt) or context.edit_prompt(prompt)
    run_prompt(full_prompt, {
        sandbox = sandbox,
        on_final = function(final_message)
            local patch = diff.extract_patch(final_message)
            if patch == "" and mode == "auto" then
                patch = context.git_diff(state.cwd)
            end
            if patch == "" then
                vim.notify("No patch found in Codex response", vim.log.levels.WARN, { title = "codex.nvim" })
                return
            end
            diff.set_patch(patch)
            M.diff()
        end,
    })
end

local function hunk_lines()
    local lines = { "# Codex Diff", "" }
    local diff_state = diff.get_state()
    for file_index, file in ipairs(diff_state.files) do
        local name = file.header[1] or ("file " .. file_index)
        lines[#lines + 1] = string.format("File %d: %s", file_index, name)
        for hunk_index, hunk in ipairs(file.hunks) do
            local mark = hunk.accepted and "[x]" or "[ ]"
            lines[#lines + 1] = string.format("  %s %d.%d %s", mark, file_index, hunk_index, hunk.header)
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "Keys: a accept hunk, r reject hunk, A accept file, R reject file, p preview, x apply accepted, q close"
    return lines
end

local function current_hunk_from_line(line)
    local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""
    local file_index, hunk_index = text:match("%s*%[[x ]%]%s+(%d+)%.(%d+)")
    if file_index and hunk_index then
        return tonumber(file_index), tonumber(hunk_index)
    end
    file_index = text:match("^File%s+(%d+):")
    if file_index then
        return tonumber(file_index), nil
    end
    return nil, nil
end

function M.diff()
    local Popup, _, event = require_nui()
    if not Popup then
        return
    end

    local popup = Popup({
        enter = true,
        focusable = true,
        relative = "editor",
        position = "50%",
        size = {
            width = math.floor(vim.o.columns * 0.82),
            height = math.floor(vim.o.lines * 0.72),
        },
        border = {
            style = config.options.ui.border,
            text = { top = " codex diff ", top_align = "center" },
        },
        buf_options = {
            buftype = "nofile",
            filetype = "markdown",
            modifiable = true,
        },
    })

    local function refresh()
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, hunk_lines())
        vim.bo[popup.bufnr].modified = false
    end

    popup:mount()
    refresh()

    local function map(lhs, rhs)
        vim.keymap.set("n", lhs, rhs, { buffer = popup.bufnr, silent = true })
    end

    map("a", function()
        local file_index, hunk_index = current_hunk_from_line(vim.fn.line("."))
        if file_index then
            diff.accept(file_index, hunk_index)
            refresh()
        end
    end)
    map("r", function()
        local file_index, hunk_index = current_hunk_from_line(vim.fn.line("."))
        if file_index then
            diff.reject(file_index, hunk_index)
            refresh()
        end
    end)
    map("A", function()
        local file_index = current_hunk_from_line(vim.fn.line("."))
        if file_index then
            diff.accept(file_index)
            refresh()
        end
    end)
    map("R", function()
        local file_index = current_hunk_from_line(vim.fn.line("."))
        if file_index then
            diff.reject(file_index)
            refresh()
        end
    end)
    map("p", function()
        local patch = diff.render(true)
        vim.cmd("tabnew")
        vim.bo.buftype = "nofile"
        vim.bo.filetype = "diff"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(patch, "\n", { plain = true }))
    end)
    map("x", function()
        local ok, message = diff.apply(state.cwd or context.cwd())
        if ok then
            vim.notify("Applied accepted hunks", vim.log.levels.INFO, { title = "codex.nvim" })
            popup:unmount()
        else
            vim.notify(message, vim.log.levels.ERROR, { title = "codex.nvim" })
        end
    end)
    map("q", function()
        popup:unmount()
    end)

    popup:on(event.BufLeave, function() end, { once = false })
end

return M
