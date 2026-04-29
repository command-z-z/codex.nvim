local M = {}

function M.lines(diff_state)
    local lines = {
        "# Codex Diff",
        "",
        "a mark accepted  r mark rejected  A accept file  R reject file  p preview  x apply to files  q close",
        "",
    }
    local line_map = {}

    for file_index, file in ipairs((diff_state or {}).files or {}) do
        local name = file.header[1] or ("file " .. file_index)
        local suffix = ""
        if file.binary then
            suffix = " (binary, whole file only)"
        elseif #file.hunks == 0 then
            suffix = " (metadata only)"
        end

        lines[#lines + 1] = string.format("File %d: %s%s", file_index, name, suffix)
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

function M.item_from_line(line_map, line)
    local item = line_map[line]
    if item then
        return item.file, item.hunk
    end

    for index = line - 1, 1, -1 do
        item = line_map[index]
        if item then
            return item.file, item.hunk
        end
    end

    return nil, nil
end

return M
