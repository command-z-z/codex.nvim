local M = {}

local state = {
    patch = "",
    files = {},
}

local function starts_with(value, prefix)
    return value:sub(1, #prefix) == prefix
end

local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    if lines[#lines] == "" then
        table.remove(lines)
    end
    return lines
end

local function new_file()
    return {
        header = {},
        hunks = {},
        accepted = true,
        binary = false,
    }
end

function M.parse(patch)
    local files = {}
    local current
    local current_hunk

    for _, line in ipairs(split_lines(patch or "")) do
        if starts_with(line, "diff --git ") then
            current = new_file()
            current.header[#current.header + 1] = line
            files[#files + 1] = current
            current_hunk = nil
        elseif current and starts_with(line, "@@") then
            current_hunk = {
                header = line,
                lines = {},
                accepted = true,
            }
            current.hunks[#current.hunks + 1] = current_hunk
        elseif current and (starts_with(line, "Binary files ") or starts_with(line, "GIT binary patch")) then
            current.binary = true
            current.header[#current.header + 1] = line
            current_hunk = nil
        elseif current_hunk then
            current_hunk.lines[#current_hunk.lines + 1] = line
        elseif current then
            current.header[#current.header + 1] = line
        end
    end

    return files
end

local function render_files(files, accepted_only)
    local out = {}
    for _, file in ipairs(files or {}) do
        local hunks = {}
        for _, hunk in ipairs(file.hunks) do
            if not accepted_only or hunk.accepted then
                hunks[#hunks + 1] = hunk
            end
        end

        if #hunks > 0 then
            vim.list_extend(out, file.header)
            for _, hunk in ipairs(hunks) do
                out[#out + 1] = hunk.header
                vim.list_extend(out, hunk.lines)
            end
        elseif (not accepted_only or file.accepted) and #file.header > 0 then
            vim.list_extend(out, file.header)
        end
    end
    if #out == 0 then
        return ""
    end
    return table.concat(out, "\n") .. "\n"
end

function M.set_patch(patch)
    state.patch = patch or ""
    state.files = M.parse(state.patch)
    return state.files
end

function M.get_state()
    return state
end

function M.set_accepted(file_index, hunk_index, accepted)
    local file = state.files[file_index]
    if not file then
        return false
    end
    if hunk_index then
        if not file.hunks[hunk_index] then
            return false
        end
        file.hunks[hunk_index].accepted = accepted
    else
        file.accepted = accepted
        for _, hunk in ipairs(file.hunks) do
            hunk.accepted = accepted
        end
    end
    return true
end

function M.accept(file_index, hunk_index)
    return M.set_accepted(file_index, hunk_index, true)
end

function M.reject(file_index, hunk_index)
    return M.set_accepted(file_index, hunk_index, false)
end

function M.render(accepted_only)
    return render_files(state.files, accepted_only)
end

function M.validate(patch, cwd)
    local result = vim.system({ "git", "apply", "--check", "--binary", "-" }, {
        cwd = cwd,
        text = true,
        stdin = patch,
    }):wait()
    return result.code == 0, result.stderr or result.stdout or ""
end

function M.apply(cwd)
    local patch = M.render(true)
    if vim.trim(patch) == "" then
        return false, "No accepted hunks to apply"
    end

    local ok, message = M.validate(patch, cwd)
    if not ok then
        return false, message
    end

    local result = vim.system({ "git", "apply", "--binary", "-" }, {
        cwd = cwd,
        text = true,
        stdin = patch,
    }):wait()
    return result.code == 0, result.stderr or result.stdout or ""
end

function M.extract_patch(text)
    if not text or text == "" then
        return ""
    end

    local fenced = text:match("```diff\n(.-)\n```") or text:match("```patch\n(.-)\n```")
    if fenced then
        return fenced
    end

    local start = text:find("diff --git ", 1, true)
    if start then
        return text:sub(start)
    end

    return ""
end

return M
