local M = {}

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

local function is_assistant_text_event(event)
    local event_type = tostring(event.type or "")
    local item = type(event.item) == "table" and event.item or {}
    local item_type = tostring(item.type or "")
    local role = tostring(event.role or item.role or "")
    local combined = event_type .. " " .. item_type

    return event_type == "agent_message"
        or event_type == "assistant_message"
        or combined:find("output_text", 1, true) ~= nil
        or (combined:find("message", 1, true) ~= nil and role == "assistant")
end

local function should_render_event(event, kind)
    if is_assistant_text_event(event) then
        return false
    end
    if kind == "error" or kind == "tool" or kind == "analysis" then
        return true
    end

    local event_type = tostring(event.type or "")
    return event_type:find("progress", 1, true) ~= nil
        or event_type:find("status", 1, true) ~= nil
        or event_type:find("reconnect", 1, true) ~= nil
end

function M.summary(event, mode)
    if type(event) ~= "table" then
        return nil
    end

    local text = first_text(event.message, event.text, event.delta, nested_text(event.error), nested_text(event.item))
    if not text or text == "" then
        return nil
    end

    local kind = event_kind(event)
    if not should_render_event(event, kind) then
        return nil
    end

    local icon = icon_for_kind(kind)
    if mode == "verbose" and event.type then
        return string.format("%s %s: %s", icon, tostring(event.type), text)
    end
    return string.format("%s %s", icon, text)
end

return M
