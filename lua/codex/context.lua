local M = {}

local function get_visual_range()
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        if start_pos[2] == 0 or end_pos[2] == 0 then
            return nil
        end
        return start_pos[2], end_pos[2]
    end

    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    return math.min(start_pos[2], end_pos[2]), math.max(start_pos[2], end_pos[2])
end

local function read_lines(bufnr, start_line, end_line)
    return vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
end

function M.selection()
    local bufnr = vim.api.nvim_get_current_buf()
    local start_line, end_line = get_visual_range()
    if not start_line or not end_line then
        return nil
    end

    local path = vim.api.nvim_buf_get_name(bufnr)
    local lines = read_lines(bufnr, start_line, end_line)
    return {
        bufnr = bufnr,
        path = path,
        start_line = start_line,
        end_line = end_line,
        text = table.concat(lines, "\n"),
    }
end

function M.current_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return {
        bufnr = bufnr,
        path = path,
        start_line = 1,
        end_line = #lines,
        text = table.concat(lines, "\n"),
    }
end

function M.diagnostics(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local items = {}
    for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
        items[#items + 1] = string.format(
            "%d:%d [%s] %s",
            diagnostic.lnum + 1,
            diagnostic.col + 1,
            vim.diagnostic.severity[diagnostic.severity] or diagnostic.severity,
            diagnostic.message
        )
    end
    return table.concat(items, "\n")
end

function M.git_diff(cwd)
    cwd = cwd or vim.uv.cwd()
    local result = vim.system({ "git", "diff", "--" }, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then
        return ""
    end
    return result.stdout or ""
end

function M.cwd()
    local git = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
    if git.code == 0 and git.stdout and git.stdout ~= "" then
        return vim.trim(git.stdout)
    end
    return vim.uv.cwd()
end

function M.build_prompt(user_prompt, opts)
    opts = opts or {}
    local parts = { user_prompt }
    local selected = opts.context or M.selection()
    local ctx = selected or (opts.include_buffer and M.current_buffer() or nil)

    if ctx and ctx.text ~= "" then
        parts[#parts + 1] = string.format(
            "\n<context file=\"%s\" lines=\"%d-%d\">\n%s\n</context>",
            ctx.path,
            ctx.start_line,
            ctx.end_line,
            ctx.text
        )
    end

    local diagnostics = M.diagnostics(ctx and ctx.bufnr or nil)
    if diagnostics ~= "" then
        parts[#parts + 1] = "\n<diagnostics>\n" .. diagnostics .. "\n</diagnostics>"
    end

    if opts.include_git_diff then
        local diff = M.git_diff(opts.cwd)
        if diff ~= "" then
            parts[#parts + 1] = "\n<git_diff>\n" .. diff .. "\n</git_diff>"
        end
    end

    return table.concat(parts, "\n")
end

return M
