local rpc_client = require("codex.rpc")

local default_opts = {
  codex_cmd = "codex",
  app_server = {
    listen_host = "127.0.0.1",
    port_range = { min = 10000, max = 65535 },
    startup_timeout_ms = 5000,
    request_timeout_ms = 120000,
    approval_policy = "never",
  },
}

local function cwd()
  return vim.fn.getcwd()
end

local M = {}

local uv = vim.uv or vim.loop

local state = {
    job_id = nil,
    rpc = nil,
    url = nil,
    connecting = false,
    initialized = false,
    waiters = {},
    stderr = {},
}

local _restart = {
  attempts   = 0,
  max        = 5,
  base_ms    = 2000,
  enabled    = true,
  timer      = nil,
}

local function executable()
  return default_opts.codex_cmd
end

local function app_config()
  return default_opts.app_server
end

local function pick_port()
    local range = app_config().port_range or {}
    local min = range.min or 10000
    local max = range.max or 65535
    math.randomseed(os.time() + math.floor((uv.now and uv.now() or 0)))
    return math.random(min, max)
end

local function notify_error(message)
    vim.notify(message, vim.log.levels.ERROR, { title = "codex.nvim" })
end

local function flush_waiters(err)
    local waiters = state.waiters
    state.waiters = {}
    if not err then
        _restart.attempts = 0
    end
    for _, waiter in ipairs(waiters) do
        waiter(state.rpc, err)
    end
end

local function schedule_restart()
  if not _restart.enabled then return end
  if _restart.attempts >= _restart.max then return end
  _restart.attempts = _restart.attempts + 1
  local delay = math.min(_restart.base_ms * (2 ^ (_restart.attempts - 1)), 30000)
  _restart.timer = vim.defer_fn(function()
    _restart.timer = nil
    if not state.job_id and _restart.enabled then
      M.ensure(function() end)
    end
  end, delay)
end

local function ensure_respond_to_server_request(method, params, respond)
    local ok, approval = pcall(require, "codex.handlers.approval")
    if ok and approval.APPROVAL_METHODS then
        for _, m in ipairs(approval.APPROVAL_METHODS) do
            if m == method then
                approval.handle(method, params, respond)
                return
            end
        end
    end
    if method:find("requestUserInput", 1, true) or method:find("elicitation", 1, true) then
        respond({ decision = "declined" })
    elseif method:find("requestApproval", 1, true) or method == "applyPatchApproval" then
        respond({ decision = "denied" })
    else
        respond(nil, { code = -32601, message = "Method not found: " .. tostring(method) })
    end
end

local function initialize(rpc, callback)
    if state.initialized then
        callback(nil)
        return
    end

    rpc:request("initialize", {
        clientInfo = {
            name = "codex.nvim",
            title = "codex.nvim",
            version = "0.1.0",
        },
        capabilities = {
            experimentalApi = true,
        },
    }, function(_, err)
        if err then
            callback(err.message or "initialize failed")
            return
        end
        state.initialized = true
        rpc:notify("initialized")
        callback(nil)
    end, app_config().request_timeout_ms)
end

local function connect_when_ready(deadline_ms)
    if not state.url then
        flush_waiters("app-server URL is not available")
        return
    end

    local rpc, err = rpc_client.connect(state.url, {
        request_timeout_ms = app_config().request_timeout_ms,
        on_open = function(opened_rpc)
            initialize(opened_rpc, function(init_err)
                if init_err then
                    flush_waiters(init_err)
                    return
                end
                flush_waiters(nil)
            end)
        end,
        on_close = function()
            state.rpc = nil
            state.initialized = false
        end,
        on_error = function(message)
            if not state.rpc and uv.now() < deadline_ms then
                vim.defer_fn(function()
                    connect_when_ready(deadline_ms)
                end, 100)
            elseif not state.rpc then
                flush_waiters(message)
            end
        end,
        on_notification = function(method, params)
            M._handle_notification(method, params)
        end,
        on_request = ensure_respond_to_server_request,
    })

    if not rpc then
        if uv.now() < deadline_ms then
            vim.defer_fn(function()
                connect_when_ready(deadline_ms)
            end, 100)
        else
            flush_waiters(err or "Failed to connect to app-server")
        end
        return
    end

    state.rpc = rpc
end

local function start_process()
    local host = app_config().listen_host or "127.0.0.1"
    local port = pick_port()
    state.url = string.format("ws://%s:%d", host, port)
    state.stderr = {}

    state.job_id = vim.fn.jobstart({
        executable(),
        "app-server",
        "--listen",
        state.url,
    }, {
        stdout_buffered = false,
        stderr_buffered = false,
        on_stderr = function(_, data)
            for _, line in ipairs(data or {}) do
                if line ~= "" then
                    state.stderr[#state.stderr + 1] = line
                end
            end
        end,
        on_exit = function(_, code)
            state.job_id = nil
            state.connecting = false
            state.rpc = nil
            state.initialized = false
            if #state.waiters > 0 then
                local stderr = table.concat(state.stderr, "\n")
                flush_waiters(stderr ~= "" and stderr or ("app-server exited with code " .. tostring(code)))
            else
                schedule_restart()
            end
        end,
    })

    return state.job_id and state.job_id > 0
end

function M.ensure(callback)
    _restart.enabled = true
    if state.rpc and state.rpc.client and state.rpc.client.state == "connected" and state.initialized then
        callback(state.rpc, nil)
        return
    end

    state.waiters[#state.waiters + 1] = callback
    if state.connecting then
        return
    end

    state.connecting = true
    if not state.job_id and not start_process() then
        state.connecting = false
        flush_waiters("Failed to start codex app-server")
        return
    end

    local deadline_ms = uv.now() + (app_config().startup_timeout_ms or 5000)
    connect_when_ready(deadline_ms)
end

local function thread_id_from_result(result)
    if type(result) ~= "table" then
        return nil
    end
    if result.threadId then
        return result.threadId
    end
    if result.thread and result.thread.id then
        return result.thread.id
    end
    if result.id then
        return result.id
    end
    return nil
end

local function start_thread(rpc, opts, callback)
    rpc:request("thread/start", {
        cwd = opts.cwd or cwd(),
        sandbox = opts.sandbox or "workspace-write",
        approvalPolicy = (app_config().approval_policy or "never"),
        model = opts.model,
        config = opts.profile and { profile = opts.profile } or nil,
        sessionStartSource = "startup",
    }, function(result, err)
        if err then
            callback(nil, err.message or "thread/start failed")
            return
        end
        local thread_id = thread_id_from_result(result)
        if not thread_id then
            callback(nil, "thread/start response did not include a thread id")
            return
        end
        callback(thread_id, nil)
    end, app_config().request_timeout_ms)
end

local function event_from_notification(method, params)
    if method == "error" then
        return {
            type = "error",
            message = params.message or params.error or "Codex app-server error",
        }
    end
    if method == "turn/started" then
        return { type = "turn.progress", message = "Started turn" }
    end
    if method == "item/started" then
        local item = params.item or {}
        if item.type == "commandExecution" or item.command then
            return {
                type = "command.started",
                item = {
                    command = item.command or item.displayCommand or "command",
                },
            }
        end
        return { type = "turn.progress", message = item.type or "Working" }
    end
    if method == "item/plan/delta" then
        return { type = "turn.progress", message = params.delta or params.text or "Planning" }
    end
    if method == "item/reasoning/summaryTextDelta" then
        return { type = "turn.progress", message = params.delta or "Reasoning" }
    end
    if method == "item/fileChange/patchUpdated" then
        return { type = "turn.progress", message = "Updated patch" }
    end
    if method == "turn/completed" then
        return nil
    end
    return nil
end

local active_turns = {}

function M._handle_notification(method, params)
    local thread_id = params.threadId or params.thread_id
    local turn_id = params.turnId or params.turn_id

    for _, turn in pairs(active_turns) do
        local matches_thread = not thread_id or thread_id == turn.thread_id
        local matches_turn = not turn_id or turn_id == turn.turn_id
        if matches_thread and matches_turn then
            if method == "turn/started" and params.turn then
                turn.turn_id = params.turn.id or params.turnId or turn.turn_id
            elseif method == "item/agentMessage/delta" then
                turn.final_parts[#turn.final_parts + 1] = params.delta or ""
            elseif method == "turn/completed" then
                turn.completed = true
                turn.finish(0, table.concat(turn.final_parts))
            end

            local event = event_from_notification(method, params)
            if event and turn.on_event then
                turn.on_event(event)
            end
        end
    end
end

function M.run_prompt(prompt, opts)
    opts = opts or {}
    M.ensure(function(rpc, err)
        if err then
            notify_error(err)
            if opts.on_exit then
                opts.on_exit(1, {}, { err }, nil)
            end
            return
        end

        start_thread(rpc, opts, function(thread_id, thread_err)
            if thread_err then
                notify_error(thread_err)
                if opts.on_exit then
                    opts.on_exit(1, {}, { thread_err }, nil)
                end
                return
            end

            local request_id
            local turn = {
                thread_id = thread_id,
                turn_id = nil,
                final_parts = {},
                on_event = opts.on_event,
            }

            turn.finish = function(code, final_message)
                if request_id then
                    active_turns[request_id] = nil
                end
                if opts.on_exit then
                    opts.on_exit(code, {}, {}, final_message)
                end
            end

            request_id = rpc:request("turn/start", {
                threadId = thread_id,
                cwd = opts.cwd or cwd(),
                sandbox = opts.sandbox or "workspace-write",
                approvalPolicy = (app_config().approval_policy or "never"),
                model = opts.model,
                input = {
                    {
                        type = "text",
                        text = prompt,
                    },
                },
            }, function(result, turn_err)
                if turn_err then
                    active_turns[request_id] = nil
                    local message = turn_err.message or "turn/start failed"
                    notify_error(message)
                    if opts.on_exit then
                        opts.on_exit(1, {}, { message }, nil)
                    end
                    return
                end
                if type(result) == "table" then
                    turn.turn_id = result.turnId or (result.turn and result.turn.id) or result.id
                end
            end, app_config().request_timeout_ms)

            active_turns[request_id] = turn
        end)
    end)
end

function M.url()
    return state.url
end

function M.stop()
    if state.rpc then
        state.rpc:close()
    end
    if state.job_id then
        pcall(vim.fn.jobstop, state.job_id)
    end
    state.job_id = nil
    state.rpc = nil
    state.url = nil
    state.connecting = false
    state.initialized = false
    state.waiters = {}
    _restart.enabled = false
    _restart.attempts = 0
    _restart.timer = nil
end

function M._event_from_notification(method, params)
    return event_from_notification(method, params or {})
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("codex_app_server_cleanup", { clear = true }),
  callback = function() M.stop() end,
})

function M._restart_state()
  return _restart
end

return M
