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
    diff_line_map = {},
    diff_popup = nil,
    progress_mode = nil,
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
    vim.api.nvim_set_hl(0, "CodexDiffAdd", { link = "DiffAdd", default = true })
    vim.api.nvim_set_hl(0, "CodexDiffDelete", { link = "DiffDelete", default = true })
    vim.api.nvim_set_hl(0, "CodexDiffHeader", { link = "DiffText", default = true })
    highlights_ready = true
end

local function apply_highlights(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    setup_highlights()
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    for index, line in ipairs(state.lines) do
        local row = index - 1
        if line:find("^## 🧑") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexUser", row, 0, -1)
        elseif line:find("^## 🤖") then
            vim.api.nvim_buf_add_highlight(bufnr, ns, "CodexAssistant", row, 0, -1)
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

local function require_nui()
    local ok_popup, Popup = pcall(require, "nui.popup")
    local ok_input, Input = pcall(require, "nui.input")
    local ok_autocmd, autocmd = pcall(require, "nui.utils.autocmd")
    if not ok_popup or not ok_input or not ok_autocmd then
        vim.notify("codex.nvim requires nui.nvim", vim.log.levels.ERROR, { title = "codex.nvim" })
        return nil
    end
    local event = autocmd.event
    return Popup, Input, event
end

local function prepare_panel_buffer(bufnr, filetype)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].filetype = filetype
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modeline = false
    vim.diagnostic.enable(false, { bufnr = bufnr })
end

local function prepare_panel_window(winid)
    if not winid or not vim.api.nvim_win_is_valid(winid) then
        return
    end

    vim.wo[winid].spell = false
end

local function append(line)
    state.lines[#state.lines + 1] = line
    if state.popup and state.popup.bufnr and vim.api.nvim_buf_is_valid(state.popup.bufnr) then
        vim.bo[state.popup.bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(state.popup.bufnr, 0, -1, false, state.lines)
        apply_highlights(state.popup.bufnr)
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

local function progress_mode()
    local progress = config.options.ui.progress or {}
    return state.progress_mode or progress.mode or "compact"
end

local function first_text(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function nested_text(value)
    if type(value) == "string" then
        return value
    end
    if type(value) ~= "table" then
        return nil
    end
    return first_text(value.message, value.text, value.title, value.name, value.command, value.status)
end

local function event_kind(event)
    local event_type = tostring(event.type or "")
    local item = type(event.item) == "table" and event.item or {}
    local item_type = tostring(item.type or "")
    local combined = event_type .. " " .. item_type
    local text = first_text(event.message, event.text, event.delta, nested_text(event.error), nested_text(event.item))

    if text and (text:find("Reconnecting", 1, true) or text:find("error", 1, true)) then
        return "error"
    end
    if combined:find("error") or combined:find("failed") then
        return "error"
    end
    if combined:find("tool") or combined:find("command") or combined:find("exec") or combined:find("function") then
        return "tool"
    end
    if combined:find("analysis") or combined:find("reason") or combined:find("plan") then
        return "analysis"
    end
    return "status"
end

local function icon_for_kind(kind)
    if kind == "error" then
        return "⚠"
    end
    if kind == "tool" then
        return "🛠"
    end
    if kind == "analysis" then
        return "🔎"
    end
    return "⏳"
end

local function event_summary(event, mode)
    if type(event) ~= "table" then
        return nil
    end

    mode = mode or progress_mode()
    local text = first_text(event.message, event.text, event.delta, nested_text(event.error), nested_text(event.item))
    if not text or text == "" then
        return nil
    end

    local kind = event_kind(event)
    local icon = icon_for_kind(kind)
    if mode == "verbose" and event.type then
        return string.format("%s %s: %s", icon, tostring(event.type), text)
    end
    return string.format("%s %s", icon, text)
end

function M._event_summary(event, mode)
    return event_summary(event, mode)
end

function M._progress_mode()
    return progress_mode()
end

function M.toggle_progress_mode()
    state.progress_mode = progress_mode() == "verbose" and "compact" or "verbose"
    append("• Progress mode: " .. state.progress_mode)
    return state.progress_mode
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

    local width = math.max(40, math.floor(vim.o.columns * 0.82))
    width = math.min(width, vim.o.columns - 4)
    local total_height = math.max(8, math.floor(vim.o.lines * 0.72))
    total_height = math.min(total_height, vim.o.lines - 4)
    local popup_height = math.max(4, total_height - 4)
    local row = math.max(1, math.floor((vim.o.lines - total_height) / 2))
    local col = math.max(1, math.floor((vim.o.columns - width) / 2))

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
            if value and value ~= "" then
                M.ask(value)
            end
        end,
    })

    state.popup:mount()
    state.input:mount()
    prepare_panel_buffer(state.popup.bufnr, "codex-chat")
    prepare_panel_window(state.popup.winid)
    if state.input and state.input.bufnr then
        prepare_panel_buffer(state.input.bufnr, "codex-prompt")
        prepare_panel_window(state.input.winid)
    end
    state.popup:on(event.BufLeave, function() end, { once = false })

    if #state.lines == 0 then
        append("# 🤖 Codex")
        append("Ready. In input: Ctrl-v toggles progress detail, Ctrl-q closes. In chat: v toggles, q closes.")
    else
        append("")
    end

    local function map_close(bufnr, mode, lhs)
        vim.keymap.set(mode, lhs, M.close, { buffer = bufnr, silent = true, desc = "Close Codex" })
    end

    map_close(state.popup.bufnr, "n", "q")
    map_close(state.popup.bufnr, "n", "<Esc>")
    vim.keymap.set("n", "v", M.toggle_progress_mode, { buffer = state.popup.bufnr, silent = true, desc = "Toggle Codex progress detail" })
    if state.input and state.input.bufnr then
        vim.keymap.set("i", "<Esc>", "<Esc>", { buffer = state.input.bufnr, silent = true, desc = "Exit input mode" })
        map_close(state.input.bufnr, "n", "q")
        map_close(state.input.bufnr, "n", "<Esc>")
        vim.keymap.set({ "n", "i" }, "<C-q>", M.close, { buffer = state.input.bufnr, silent = true, desc = "Close Codex" })
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

local function run_prompt(prompt, opts)
    opts = opts or {}
    M.open()
    state.cwd = opts.cwd or context.cwd()
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
                append(line)
            end
        end,
        on_exit = function(code, _, stderr, final_message)
            if code ~= 0 then
                append_block("⚠ Error", table.concat(stderr or {}, "\n"))
                return
            end
            append_block("🤖 Codex", final_message or "")
            if opts.on_final then
                opts.on_final(final_message or "")
            end
        end,
    })
end

function M.ask(prompt)
    local full_prompt = context.build_prompt(prompt, { include_buffer = false, include_git_diff = false })
    run_prompt(full_prompt, {
        display_prompt = prompt,
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
        display_prompt = prompt,
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

local function diff_view_lines()
    local lines = {
        "# Codex Diff",
        "",
        "a mark accepted  r mark rejected  A accept file  R reject file  p preview  x apply to files  q close",
        "",
    }
    local line_map = {}
    local diff_state = diff.get_state()
    for file_index, file in ipairs(diff_state.files) do
        local name = file.header[1] or ("file " .. file_index)
        lines[#lines + 1] = string.format("File %d: %s", file_index, name)
        line_map[#lines] = { file = file_index }

        for _, header in ipairs(file.header) do
            lines[#lines + 1] = header
            line_map[#lines] = { file = file_index }
        end

        for hunk_index, hunk in ipairs(file.hunks) do
            local mark = hunk.accepted and "✓ accepted" or "✗ rejected"
            lines[#lines + 1] = string.format("%s %d.%d %s", mark, file_index, hunk_index, hunk.header)
            line_map[#lines] = { file = file_index, hunk = hunk_index }

            for _, line in ipairs(hunk.lines) do
                lines[#lines + 1] = line
                line_map[#lines] = { file = file_index, hunk = hunk_index }
            end
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = ""
    end
    return lines, line_map
end

local function current_hunk_from_line(line)
    local item = state.diff_line_map[line]
    if item then
        return item.file, item.hunk
    end

    for index = line - 1, 1, -1 do
        item = state.diff_line_map[index]
        if item then
            return item.file, item.hunk
        end
    end

    return nil, nil
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
            filetype = "codex-diff",
            modifiable = false,
        },
    })
    state.diff_popup = popup

    local function refresh()
        local cursor = vim.api.nvim_win_is_valid(popup.winid) and vim.api.nvim_win_get_cursor(popup.winid) or { 1, 0 }
        local lines, line_map = diff_view_lines()
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
    prepare_panel_buffer(popup.bufnr, "codex-diff")
    prepare_panel_window(popup.winid)
    refresh()

    local function map(lhs, rhs)
        vim.keymap.set("n", lhs, rhs, { buffer = popup.bufnr, silent = true })
    end

    map("a", function()
        local file_index, hunk_index = current_hunk_from_line(vim.fn.line("."))
        if file_index and hunk_index then
            diff.accept(file_index, hunk_index)
            refresh()
            vim.notify("Marked hunk as accepted. Press x to apply accepted hunks.", vim.log.levels.INFO, { title = "codex.nvim" })
        else
            vim.notify("Move the cursor onto a hunk to accept it", vim.log.levels.INFO, { title = "codex.nvim" })
        end
    end)
    map("r", function()
        local file_index, hunk_index = current_hunk_from_line(vim.fn.line("."))
        if file_index and hunk_index then
            diff.reject(file_index, hunk_index)
            refresh()
            vim.notify("Marked hunk as rejected. Press x to apply accepted hunks.", vim.log.levels.INFO, { title = "codex.nvim" })
        else
            vim.notify("Move the cursor onto a hunk to reject it", vim.log.levels.INFO, { title = "codex.nvim" })
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
