local M = {}

function M.split(args)
    if not args or args == "" then
        return {}
    end

    local out = {}
    local current = {}
    local quote = nil
    local escaped = false

    for index = 1, #args do
        local char = args:sub(index, index)
        if escaped then
            current[#current + 1] = char
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif quote then
            if char == quote then
                quote = nil
            else
                current[#current + 1] = char
            end
        elseif char == '"' or char == "'" then
            quote = char
        elseif char:match("%s") then
            if #current > 0 then
                out[#out + 1] = table.concat(current)
                current = {}
            end
        else
            current[#current + 1] = char
        end
    end

    if escaped then
        current[#current + 1] = "\\"
    end
    if #current > 0 then
        out[#out + 1] = table.concat(current)
    end

    return out
end

return M
