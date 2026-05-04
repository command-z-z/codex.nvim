local cli = require("codex.cli")
local config = require("codex.config")
local context = require("codex.context")
local diff = require("codex.diff")
local diff_view = require("codex.ui.diff_view")
local events = require("codex.ui.events")
local panel = require("codex.ui.panel")

local M = {}

local state = {
    popup = nil,
    input = nil,
    lines = {},
    cwd = nil,
    diff_line_map = {},
    diff_popup = nil,
    progress_mode = nil,
    pending_context = nil,
    event_lines = {},
}

local ns = vim.api.nvim_create_namespace("codex.nvim")
local highlights_ready = false

local function setup_highlights()
    if highlights_ready then
        return
    end

    vim.api.nvim_set_hl(0, "CodexUser", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "CodexAssistant", { link = "Identifier", default = true })
    vim.api.nvim_set_hl(0, "CodexError", { link = "ErrorMsg", default = true })
    vim.api.nvim_set_hl(0, "CodexStatus", { link = "WarningMsg", default = true })
    vim.api.nvim_set_hl(0, "CodexProgress", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "CodexTool", { link = "Function", default = true })
    vim.api.nvim_set_hl(0, "CodexContextBlock", { bg = "#30384d", default = true })
    vim.api.nvim_set_hl(0, "CodexContextBorder", { fg = "#89b4fa", bg = "#30384d", default = true })
    vim.api.nvim_set_hl(0, "CodexContextLabel", { fg = "#f9e2af", bg = "#30384d", bold = true, default = true })
    vim.api.nvim_set_hl(0, "CodexContextValue", { fg = "#cdd6f4", bg = "#30384d", default = true })
    vim.api.nvim_set_hl(0, "CodexDiffAdd", { link = "DiffAdd", default = true })
    vim.api.nvim_set_hl(0, "CodexDiffDelete", { link = "DiffDelete", default = true })
    vim.api.nvim_set_hl(0, "CodexDiffHeader", { link = "DiffText", default = true })
    highlights_ready = true
end

local function apply_highlights(bufnr, start_index)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    setup_highlights()
    start_index = start_index or 1
    vim.api.nvim_buf_clear_namespace(bufnr, ns, start_index - 1, -1)

    for index = start_index, #state.lines do
        local line = state.lines[index]
        local row = index - 1
        if line:find("^## 🧑") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexUser", row, 0, -1)
        elseif line:find("^## 🤖") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexAssistant", row, 0, -1)
        elseif line:find("^╭") or line:find("^╰") then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                line_hl_group = "CodexContextBlock",
            })
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexContextBorder", row, 0, -1)
        elseif line:find("^│") then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                line_hl_group = "CodexContextBlock",
            })
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexContextBorder", row, 0, -1)
            local label_start, label_end = line:find("%w+:")
            if label_start and label_end then
                vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexContextLabel", row, label_start - 1, label_end)
                vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexContextValue", row, label_end + 1, -2)
            end
        elseif line:find("^## ⚠") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexError", row, 0, -1)
        elseif line:find("^Codex is running") or line:find("^⏳") or line:find("^🔎") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexStatus", row, 0, -1)
        elseif line:find("^🛠") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexTool", row, 0, -1)
        elseif line:find("^⚠") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexError", row, 0, -1)
        elseif line:find("^•") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexProgress", row, 0, -1)
        elseif line:find("^%+") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexDiffAdd", row, 0, -1)
        elseif line:find("^%-") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexDiffDelete", row, 0, -1)
        elseif line:find("^@@") or line:find("^diff %-%-git") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexDiffHeader", row, 0, -1)
        end
    end
end

local function split_display_lines(value)
    local text = tostring(value or "")
    return vim.split(text, "\n", { plain = true })
end

local function refresh_output(start_index)
    if not state.popup or not state.popup.bufnr or not vim.api.nvim_buf_is_valid(state.popup.bufnr) then
        return
    end

    vim.bo[state.popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(state.popup.bufnr, 0, -1, false, state.lines)
    apply_highlights(state.popup.bufnr, start_index)
    vim.bo[state.popup.bufnr].modifiable = false
    if state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
        local line_count = vim.api.nvim_buf_line_count(state.popup.bufnr)
        vim.api.nvim_win_set_cursor(state.popup.winid, { math.min(math.max(1, #state.lines), line_count), 0 })
    end
end

local function append(line)
    local old_count = #state.lines
    local display_lines = split_display_lines(line)
    for _, display_line in ipairs(display_lines) do
        state.lines[#state.lines + 1] = display_line
    end

    if state.popup and state.popup.bufnr and vim.api.nvim_buf_is_valid(state.popup.bufnr) then
        local line_count = vim.api.nvim_buf_line_count(state.popup.bufnr)
        vim.bo[state.popup.bufnr].modifiable = true
        if old_count == 0 or line_count < old_count then
            vim.api.nvim_buf_set_lines(state.popup.bufnr, 0, -1, false, state.lines)
        else
            vim.api.nvim_buf_set_lines(state.popup.bufnr, old_count, old_count, false, display_lines)
        end
        apply_highlights(state.popup.bufnr, old_count + 1)
        vim.bo[state.popup.bufnr].modifiable = false
        if state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
            line_count = vim.api.nvim_buf_line_count(state.popup.bufnr)
            vim.api.nvim_win_set_cursor(state.popup.winid, { math.min(math.max(1, #state.lines), line_count), 0 })
        end
    end
end

local function append_event(line)
    if state.event_lines.last == line then
        return
    end
    state.event_lines.last = line
    append(line)
end

local function append_block(title, text)
    append("")
    append("## " .. title)
    for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
        append(line)
    end
end

local function remove_trailing_block(text)
    local lines = split_display_lines(text)
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    if #lines == 0 or #state.lines < #lines then
        return false
    end

    local state_index = #state.lines
    while state_index > 0 and state.lines[state_index] == "" do
        state_index = state_index - 1
    end
    if state_index < #lines then
        return false
    end

    for index = #lines, 1, -1 do
        if state.lines[state_index] ~= lines[index] then
            return false
        end
        state_index = state_index - 1
    end

    for _ = state_index + 1, #state.lines do
        state.lines[#state.lines] = nil
    end
    refresh_output(state_index + 1)
    return true
end

local function relative_path(path)
    if not path or path == "" then
        return "[No Name]"
    end
    local cwd = context.cwd()
    if vim.startswith(path, cwd .. "/") then
        return path:sub(#cwd + 2)
    end
    return path
end

local function context_summary(ctx)
    if not ctx then
        return ""
    end

    local lines = vim.split(ctx.text or "", "\n", { plain = true })
    local body = {
        string.format("File: %s", relative_path(ctx.path)),
        string.format("Lines: %d-%d (%d lines)", ctx.start_line, ctx.end_line, #lines),
    }
    local width = #" Select Block "
    for _, line in ipairs(body) do
        width = math.max(width, #line)
    end

    local block = {
        "╭─ Select Block " .. string.rep("─", width - #" Select Block ") .. "╮",
    }
    for _, line in ipairs(body) do
        block[#block + 1] = "│ " .. line .. string.rep(" ", width - #line) .. " │"
    end
    block[#block + 1] = "╰" .. string.rep("─", width + 2) .. "╯"

    return table.concat(block, "\n")
end

local function progress_mode()
    local progress = config.options.ui.progress or {}
    return state.progress_mode or progress.mode or "compact"
end

local function event_summary(event, mode)
    return events.summary(event, mode or progress_mode())
end

function M._event_summary(event, mode)
    return event_summary(event, mode)
end

function M._progress_mode()
    return progress_mode()
end

function M._context_summary(ctx)
    return context_summary(ctx)
end

function M._split_display_lines(value)
    return split_display_lines(value)
end

function M._remove_trailing_block(text)
    return remove_trailing_block(text)
end

function M._append_event(line)
    append_event(line)
end

function M.toggle_progress_mode()
    state.progress_mode = progress_mode() == "verbose" and "compact" or "verbose"
    append("• Progress mode: " .. state.progress_mode)
    return state.progress_mode
end

local function popup_valid()
    return state.popup and state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid)
end

local function input_valid()
    return state.input and state.input.winid and vim.api.nvim_win_is_valid(state.input.winid)
end

function M.focus_output()
    if popup_valid() then
        vim.api.nvim_set_current_win(state.popup.winid)
    end
end

function M.focus_prompt()
    if input_valid() then
        vim.api.nvim_set_current_win(state.input.winid)
        vim.cmd("startinsert")
    end
end

function M.open()
    local Popup, Input, event = panel.require_nui()
    if not Popup then
        return
    end

    local width = math.max(40, math.floor(vim.o.columns * 0.82))
    width = math.min(width, vim.o.columns - 4)
    local total_height = math.max(8, math.floor(vim.o.lines * 0.72))
    total_height = math.min(total_height, vim.o.lines - 4)
    local popup_height = math.max(4, total_height - 4)
    local row = math.max(1, math.floor((vim.o.lines - total_height) / 2))
    local col = math.max(1, math.floor((vim.o.columns - width) / 2))

    local created_popup = false
    if not popup_valid() then
        state.popup = Popup({
            enter = false,
            focusable = true,
            relative = "editor",
            position = "50%",
            size = {
                width = width,
                height = popup_height,
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
                filetype = "codex-chat",
                modifiable = false,
            },
        })
        state.popup:mount()
        panel.prepare_buffer(state.popup.bufnr, "codex-chat")
        panel.prepare_window(state.popup.winid)
        state.popup:on(event.BufLeave, function() end, { once = false })
        created_popup = true
    else
        vim.api.nvim_set_current_win(state.popup.winid)
    end

    local function map_close(bufnr, mode, lhs)
        vim.keymap.set(mode, lhs, M.close, { buffer = bufnr, silent = true, desc = "Close Codex" })
    end

    if created_popup then
        if #state.lines == 0 then
            append("# 🤖 Codex")
            append("Ready. Type your prompt below. Ctrl-v toggles progress detail, Ctrl-q closes.")
        else
            append("")
        end

        map_close(state.popup.bufnr, "n", "q")
        map_close(state.popup.bufnr, "n", "<Esc>")
        local ui_keymaps = config.options.ui.keymaps or {}
        if ui_keymaps.focus_prompt then
            vim.keymap.set("n", ui_keymaps.focus_prompt, M.focus_prompt, { buffer = state.popup.bufnr, silent = true, desc = "Focus Codex prompt" })
        end
        vim.keymap.set("n", "v", M.toggle_progress_mode, { buffer = state.popup.bufnr, silent = true, desc = "Toggle Codex progress detail" })
    end

    if not input_valid() then
        state.input = Input({
            relative = "editor",
            position = {
                row = row + popup_height + 2,
                col = col,
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
                state.input = nil
                if value and value ~= "" then
                    local pending_context = state.pending_context
                    state.pending_context = nil
                    M.ask(value, { context = pending_context })
                else
                    M.open()
                end
            end,
        })

        state.input:mount()
        panel.prepare_input_buffer(state.input.bufnr)
        panel.prepare_window(state.input.winid)
        vim.keymap.set("i", "<Esc>", "<Esc>", { buffer = state.input.bufnr, silent = true, desc = "Exit input mode" })
        map_close(state.input.bufnr, "n", "q")
        map_close(state.input.bufnr, "n", "<Esc>")
        local ui_keymaps = config.options.ui.keymaps or {}
        vim.keymap.set({ "n", "i" }, "<C-q>", M.close, { buffer = state.input.bufnr, silent = true, desc = "Close Codex" })
        if ui_keymaps.focus_output then
            vim.keymap.set({ "n", "i" }, ui_keymaps.focus_output, M.focus_output, { buffer = state.input.bufnr, silent = true, desc = "Focus Codex output" })
        end
        vim.keymap.set({ "n", "i" }, "<C-v>", M.toggle_progress_mode, { buffer = state.input.bufnr, silent = true, desc = "Toggle Codex progress detail" })
        vim.keymap.set("n", "v", M.toggle_progress_mode, { buffer = state.input.bufnr, silent = true, desc = "Toggle Codex progress detail" })
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

function M.toggle()
    if state.popup and state.popup.winid and vim.api.nvim_win_is_valid(state.popup.winid) then
        M.close()
        return
    end

    M.open()
end

function M.attach_selection()
    local selected = context.selection()
    if not selected or selected.text == "" then
        vim.notify("Select code before attaching Codex context", vim.log.levels.WARN, { title = "codex.nvim" })
        return
    end

    state.pending_context = selected
    M.open()
    append("")
    append(context_summary(selected))

    if state.input and state.input.winid and vim.api.nvim_win_is_valid(state.input.winid) then
        vim.api.nvim_set_current_win(state.input.winid)
        vim.cmd("startinsert")
    end
end

local function run_prompt(prompt, opts)
    opts = opts or {}
    M.open()
    state.cwd = opts.cwd or context.cwd()
    state.event_lines = {}
    append_block("🧑 You", opts.display_prompt or prompt)
    append("")
    append("Codex is running...")

    cli.exec_json(prompt, {
        cwd = state.cwd,
        sandbox = opts.sandbox,
        output_last_message = true,
        on_event = function(event)
            local line = event_summary(event, progress_mode())
            if line and line ~= "" then
                append_event(line)
            end
        end,
        on_exit = function(code, _, stderr, final_message)
            if code ~= 0 then
                append_block("⚠ Error", table.concat(stderr or {}, "\n"))
                return
            end
            remove_trailing_block(final_message or "")
            append_block("🤖 Codex", final_message or "")
            if opts.on_final then
                opts.on_final(final_message or "")
            end
        end,
    })
end

local function open_diff_from_message(final_message, opts)
    opts = opts or {}
    local patch = diff.extract_patch(final_message)
    if patch == "" and opts.fallback_git_diff then
        patch = context.git_diff(state.cwd)
    end
    if patch == "" then
        return false
    end

    diff.set_patch(patch)
    M.diff()
    return true
end

function M.ask(prompt, opts)
    opts = opts or {}
    local full_prompt = context.build_prompt(prompt, {
        include_buffer = false,
        include_git_diff = false,
        context = opts.context,
    })
    run_prompt(full_prompt, {
        display_prompt = prompt,
        sandbox = opts.sandbox or config.options.chat.sandbox,
        on_final = function(final_message)
            open_diff_from_message(final_message)
        end,
    })
end

function M._open_diff_from_message(final_message, opts)
    return open_diff_from_message(final_message, opts)
end

local function highlight_diff_view(bufnr)
    setup_highlights()
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for index, line in ipairs(lines) do
        local row = index - 1
        if line:find("^✓") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexDiffAdd", row, 0, -1)
        elseif line:find("^✗") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexDiffDelete", row, 0, -1)
        elseif line:find("^%+") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffAdd", row, 0, -1)
        elseif line:find("^%-") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffDelete", row, 0, -1)
        elseif line:find("^@@") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffText", row, 0, -1)
        elseif line:find("^diff %-%-git") or line:find("^File %d+:") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", row, 0, -1)
        elseif line:find("^a accept") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)
        end
    end
end

function M.diff()
    if state.diff_popup and state.diff_popup.winid and vim.api.nvim_win_is_valid(state.diff_popup.winid) then
        vim.api.nvim_set_current_win(state.diff_popup.winid)
        return
    end

    local Popup, _, event = panel.require_nui()
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
            filetype = "codex-diff",
            modifiable = false,
        },
    })
    state.diff_popup = popup

    local function refresh()
        local cursor = vim.api.nvim_win_is_valid(popup.winid) and vim.api.nvim_win_get_cursor(popup.winid) or { 1, 0 }
        local lines, line_map = diff_view.lines(diff.get_state())
        state.diff_line_map = line_map
        vim.bo[popup.bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
        highlight_diff_view(popup.bufnr)
        vim.bo[popup.bufnr].modifiable = false
        vim.bo[popup.bufnr].modified = false
        if vim.api.nvim_win_is_valid(popup.winid) then
            local row = math.min(cursor[1], #lines)
            vim.api.nvim_win_set_cursor(popup.winid, { math.max(1, row), cursor[2] })
        end
    end

    popup:mount()
    panel.prepare_buffer(popup.bufnr, "codex-diff")
    panel.prepare_window(popup.winid)
    refresh()

    local function map(lhs, rhs)
        vim.keymap.set("n", lhs, rhs, { buffer = popup.bufnr, silent = true })
    end

    map("a", function()
        local file_index, hunk_index = diff_view.item_from_line(state.diff_line_map, vim.fn.line("."))
        if file_index and hunk_index then
            diff.accept(file_index, hunk_index)
            refresh()
            vim.notify("Marked hunk as accepted. Press x to apply accepted hunks.", vim.log.levels.INFO, { title = "codex.nvim" })
        else
            vim.notify("Move the cursor onto a hunk to accept it", vim.log.levels.INFO, { title = "codex.nvim" })
        end
    end)
    map("r", function()
        local file_index, hunk_index = diff_view.item_from_line(state.diff_line_map, vim.fn.line("."))
        if file_index and hunk_index then
            diff.reject(file_index, hunk_index)
            refresh()
            vim.notify("Marked hunk as rejected. Press x to apply accepted hunks.", vim.log.levels.INFO, { title = "codex.nvim" })
        else
            vim.notify("Move the cursor onto a hunk to reject it", vim.log.levels.INFO, { title = "codex.nvim" })
        end
    end)
    map("A", function()
        local file_index = diff_view.item_from_line(state.diff_line_map, vim.fn.line("."))
        if file_index then
            diff.accept(file_index)
            refresh()
        end
    end)
    map("R", function()
        local file_index = diff_view.item_from_line(state.diff_line_map, vim.fn.line("."))
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
            vim.cmd("checktime")
            vim.notify("Applied accepted hunks to files", vim.log.levels.INFO, { title = "codex.nvim" })
            popup:unmount()
            state.diff_popup = nil
        else
            vim.notify(message, vim.log.levels.ERROR, { title = "codex.nvim" })
        end
    end)
    map("q", function()
        popup:unmount()
        state.diff_popup = nil
    end)

    popup:on(event.BufLeave, function() end, { once = false })
end

function M.diff_toggle()
    if state.diff_popup and state.diff_popup.winid and vim.api.nvim_win_is_valid(state.diff_popup.winid) then
        state.diff_popup:unmount()
        state.diff_popup = nil
        return
    end

    M.diff()
end

return M
