# 重构 codex.nvim 与 claudecode.nvim 行为一致

## Context

让 codex.nvim 在使用上与 claudecode.nvim **切换无感** —— 命令、UI 行为、配置形状、交互节奏全部对齐。基于前一次综合分析，已经认清：Codex CLI 不说 MCP，"IPC 完全一致"做不到，但**架构镜像 + 行为对齐**可以让用户主观上感觉不到区别。

本文档描述如何把现有 codex.nvim（~2.5k 行，依赖 plenary + nui）推倒重写为一个镜像 claudecode.nvim 模块边界、纯 Lua 零依赖、走 codex app-server 持久 WebSocket 连接的新插件。

## 锁定的决策（来自 brainstorming）

| 决策点 | 选择 |
|--------|------|
| 路线 | 架构镜像 + 原生 IPC（保留 Codex 协议，对齐模块/命令/UI） |
| 移植范围 | 8/9 项核心交互（**不**移植文件树 5 件套） |
| Backend | `app_server` 唯一，移除 `exec_json` |
| 依赖 | 纯 Lua，干掉 `plenary` 与 `nui` |
| 代码组织 | 推倒重写（清空 `lua/codex/`） |
| 命令名 | `:Codex*` 词尾动词对齐 `:ClaudeCode*` |
| Approval | 映射为阻塞式 UI prompt（默认 `prompt`，可配 `auto-deny`/`auto-allow`） |

## 目标目录结构

镜像 claudecode.nvim 的模块边界，名称按 Codex 角色调整（Neovim 是 WS **客户端**，不是 server）：

```
codex.nvim/
├── plugin/codex.lua              # 加载入口 + 版本检查
├── lua/codex/
│   ├── init.lua                  # 入口、命令注册、@mention 队列、setup()
│   ├── config.lua                # 默认值 + 校验
│   ├── transport/                # WebSocket 客户端栈（连 codex app-server）
│   │   ├── init.lua              # 主门面
│   │   ├── tcp.lua               # vim.loop TCP client (connect 而非 listen)
│   │   ├── handshake.lua         # WS client handshake (生成 Sec-WS-Key)
│   │   ├── frame.lua             # RFC 6455 帧解析（与 claudecode.nvim 同源逻辑）
│   │   ├── session.lua           # 单连接状态机
│   │   └── utils.lua             # 纯 Lua SHA-1 + Base64
│   ├── rpc.lua                   # JSON-RPC 2.0（request/response/notification）
│   ├── app_server.lua            # codex app-server 子进程生命周期
│   ├── handlers/                 # Codex → Neovim 上行事件分发
│   │   ├── init.lua              # notification dispatcher
│   │   ├── approval.lua          # 阻塞式 approval prompt
│   │   ├── progress.lua          # 进度事件渲染（compact/verbose）
│   │   └── diff_apply.lua        # 收到补丁 → 触发 diff UI
│   ├── context.lua               # 选区/buffer/diagnostics/git_diff 上下文构建
│   ├── terminal.lua              # provider 抽象
│   ├── terminal/
│   │   ├── snacks.lua            # snacks.nvim provider
│   │   ├── native.lua            # 内置 terminal 兜底
│   │   └── external.lua          # 外部 terminal 启动
│   ├── diff.lua                  # 阻塞式 diff 视图 + hunk 级 review（保留优势）
│   ├── selection.lua             # 实时选区追踪 + 50ms debounce 推送
│   ├── visual_commands.lua       # :'<,'>CodexSend 等 range 命令
│   ├── logger.lua                # 结构化日志
│   ├── utils.lua                 # 通用工具
│   └── types.lua                 # LuaLS 类型注解
├── tests/                        # busted 测试（无需 plenary）
│   ├── unit/
│   ├── integration/
│   └── mocks/                    # 自实现 vim API mock（参考 claudecode.nvim）
├── PROTOCOL.md                   # codex app-server 协议笔记（逆向产物）
├── ARCHITECTURE.md
└── README.md                     # 含老用户迁移指南
```

## 命令对照表

镜像原则：保留 `:Codex` 前缀，词尾动词对齐 `:ClaudeCode*`。

| 新命令 | 对应 claudecode.nvim | 行为 | 状态 |
|-------|---------------------|------|------|
| `:Codex` | `:ClaudeCode` | 切换面板 | 重命名（原 `:Codex` 是 panel open） |
| `:Codex --resume` | `:ClaudeCode --resume` | 恢复上一个 codex 会话 | 新增（flag 形式） |
| `:Codex --continue` | `:ClaudeCode --continue` | 继续最近 codex 会话 | 新增（flag 形式） |
| `:CodexFocus` | `:ClaudeCodeFocus` | 智能 focus toggle | 新增 |
| `:CodexOpen` | `:ClaudeCodeOpen` | 打开面板（始终可见） | 新增 |
| `:CodexClose` | `:ClaudeCodeClose` | 关闭面板 | 重命名（原 `:CodexClose`） |
| `:CodexAdd <file> [start] [end]` | `:ClaudeCodeAdd` | 加文件/行范围到上下文 | 新增 |
| `:CodexSend` | `:ClaudeCodeSend` | 发送当前 visual selection | 新增 |
| `:CodexDiffAccept` | `:ClaudeCodeDiffAccept` | 接受 diff 写盘 | 新增（替代 hunk `a` 全部） |
| `:CodexDiffDeny` | `:ClaudeCodeDiffDeny` | 拒绝 diff | 新增（替代 hunk `r` 全部） |
| `:CodexSelectModel` | `:ClaudeCodeSelectModel` | 模型选择 | 新增 |
| `:CodexStart` | `:ClaudeCodeStart` | 手动启动 app-server | 新增 |
| `:CodexStop` | `:ClaudeCodeStop` | 停止 | 新增 |
| `:CodexStatus` | `:ClaudeCodeStatus` | 连接状态 | 新增 |

**移除的老命令**：`:CodexCLI`、`:CodexCLIToggle`、`:CodexResume`、`:CodexDiff`、`:CodexDiffToggle`、`:CodexToggle`、`:CodexApply` 全部移除。

**迁移建议**：

| 老命令 | 新做法 |
|-------|-------|
| `:CodexCLI` / `:CodexCLIToggle` | 用 `:Codex` 切面板，或老用户自行用 `:terminal codex` |
| `:CodexResume` | `:Codex --resume`（在面板里恢复，不再走浮窗 TUI） |
| `:CodexDiff` / `:CodexDiffToggle` | diff 在 codex 推送补丁时自动开；手动可用 `:CodexDiffAccept`/`:CodexDiffDeny` |
| `:CodexApply` | 由 `:CodexDiffAccept` 隐含 |
| `:CodexToggle` | `:Codex` |

**推荐 keymap**（与 claudecode.nvim 完全镜像）：

```lua
{ "<leader>aa", "<cmd>Codex<cr>",            desc = "Toggle Codex" },
{ "<leader>ar", "<cmd>Codex --resume<cr>",   desc = "Resume Codex" },
{ "<leader>aC", "<cmd>Codex --continue<cr>", desc = "Continue Codex" },
{ "<leader>af", "<cmd>CodexFocus<cr>",       desc = "Focus Codex" },
{ "<leader>as", "<cmd>CodexSend<cr>",        mode = { "n", "v" }, desc = "Send to Codex" },
```

**过渡期**：所有移除的命令在 0.x 期间保留为 wrapper，调用时 `vim.notify` 提示新名，1.0 时删除。

## 配置形状

镜像 claudecode.nvim 的 setup 形状，Codex 特有项独立成块：

```lua
require("codex").setup({
  -- Server 配置
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  codex_cmd = "codex",
  env = {},
  log_level = "info",

  -- 选区与交互
  track_selection = true,
  visual_demotion_delay_ms = 50,
  focus_after_send = false,

  -- 连接管理
  connection_wait_delay = 600,
  connection_timeout = 10000,
  queue_timeout = 5000,

  -- Diff 显示（保留 hunk-level 优势）
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false,
    keep_terminal_focus = false,
    on_new_file_reject = "keep_empty",
    hunk_level_review = true,           -- Codex 特有
  },

  -- 终端
  terminal = {
    provider = "auto",                  -- "snacks" | "native" | "external" | "none"
    split_side = "right",
    split_width_percentage = 0.30,
    snacks_win_opts = {},
    auto_close = true,
    cwd_provider = nil,
    git_repo_cwd = true,
    provider_opts = { external_terminal_cmd = nil },
  },

  -- Codex 特有
  approval = {
    policy = "prompt",                  -- "prompt" | "auto-deny" | "auto-allow"
    sandbox = "workspace-write",
  },

  models = {
    { name = "GPT-5 Codex", value = "gpt-5-codex" },
    -- ...
  },
})
```

## 分阶段执行计划

每阶段独立 PR，可单独 review、单独 ship。总计 **14-19 个工作日 ≈ 3-4 周**。

### Phase 0 — 准备 (0.5d)
- 在 `docs/specs/` 写下设计文档（本文件）
- `git tag pre-rewrite` 标记当前版本
- 清空 `lua/codex/`，保留 `plugin/codex.lua` 的加载逻辑
- 删除 README 中老命令文档，准备迁移指南框架

**关键文件**：`plugin/codex.lua`（保留）、`docs/specs/refactor-design.md`（本文件）

### Phase 1 — 传输层 (3-4d)
- `lua/codex/transport/utils.lua` — 纯 Lua SHA-1 + Base64（**复用 claudecode.nvim/lua/claudecode/server/utils.lua 的算法**，但作为 client 角色不需要 server-side accept-key 验证）
- `lua/codex/transport/frame.lua` — RFC 6455 帧编解码（**直接借鉴 claudecode.nvim/lua/claudecode/server/frame.lua**）
- `lua/codex/transport/handshake.lua` — client handshake（生成 random Sec-WebSocket-Key，验证 server 返回的 accept hash）
- `lua/codex/transport/tcp.lua` — `vim.loop.new_tcp() + :connect()`（区别于 claudecode.nvim 的 listen）
- `lua/codex/transport/session.lua` — 单连接状态机：connecting/handshaking/open/closing/closed，30s ping/pong 心跳
- `lua/codex/rpc.lua` — JSON-RPC 2.0（沿用现有 codex.nvim/lua/codex/rpc.lua 逻辑，去 plenary 化）
- `lua/codex/app_server.lua` — spawn `codex app-server --listen ws://127.0.0.1:PORT`，端口扫描、健康检查、退出清理（去 plenary.job 化，用 `vim.system` + `vim.loop`）

**关键文件**：`lua/codex/transport/*.lua`、`lua/codex/rpc.lua`、`lua/codex/app_server.lua`

**复用引用**：
- `claudecode.nvim/lua/claudecode/server/utils.lua` — SHA-1/Base64 算法
- `claudecode.nvim/lua/claudecode/server/frame.lua` — frame parser
- `codex.nvim/lua/codex/websocket.lua`（pre-rewrite tag）— client-side WS 已实现，可作蓝本但需重组
- `codex.nvim/lua/codex/rpc.lua`（pre-rewrite tag）— JSON-RPC 已实现，仅去依赖

**测试**：mock 一个 vim.loop WebSocket server，端到端 ping/pong + 一个 RPC roundtrip。

### Phase 2 — 核心面板 + 命令 (2-3d)
- `lua/codex/init.lua` — `setup(opts)`，注册全部新命令（按对照表），全局 state 表（server、port、@mention queue）
- `lua/codex/config.lua` — 默认值 + 校验，迁移老配置 key 时输出 deprecation warning
- `lua/codex/terminal.lua` — provider 接口定义：`open/close/simple_toggle/focus_toggle/get_active_bufnr/is_available`（**镜像 claudecode.nvim/lua/claudecode/terminal.lua**）
- `lua/codex/terminal/native.lua` — 内置 terminal 兜底（`vim.api.nvim_open_term`）
- `lua/codex/terminal/snacks.lua` — snacks.nvim 适配
- `lua/codex/terminal/external.lua` — alacritty/iTerm 启动

**关键文件**：`lua/codex/init.lua`、`lua/codex/config.lua`、`lua/codex/terminal.lua`、`lua/codex/terminal/{native,snacks,external}.lua`

### Phase 3 — 上下文与选区 (2d)
- `lua/codex/selection.lua` — autocmd 监听 `CursorMoved`/`ModeChanged`，50ms debounce，选区变化通过 RPC notification 推 `selection_changed` 给 codex app-server（**镜像 claudecode.nvim/lua/claudecode/selection.lua**）
- `lua/codex/context.lua` — 沿用 pre-rewrite tag 的上下文构建（buffer/range/diagnostics/git_diff），去 plenary 化
- `lua/codex/visual_commands.lua` — visual range 命令包装（`:'<,'>CodexSend` 等），mode 切出前捕获 selection（**镜像 claudecode.nvim/lua/claudecode/visual_commands.lua**）
- 实现 `:CodexAdd <file> [start] [end]` 的 1-indexed 行号支持

**测试**：选区追踪 debounce 触发次数；visual range 命令在 mode 切换时正确捕获。

### Phase 4 — 阻塞式 diff (3-4d)
- `lua/codex/diff.lua` —
  - 解析 unified diff 为 file/hunk 树（沿用 pre-rewrite tag 的 parser）
  - 打开侧边对比窗口（vertical/horizontal），**hunk 级 review UI** 保留（`a`/`r`/`A`/`R`/`p`/`x` keymaps）
  - **阻塞式响应**：收到 codex app-server 推来的 file change 事件 → 打开 diff → 等用户 `:CodexDiffAccept` 或 `:CodexDiffDeny` → RPC 回包给 codex
  - smart window selection（避开 terminal/sidebar/floating）
  - on_new_file_reject 行为
- `lua/codex/handlers/diff_apply.lua` — 接收 codex 的 fileChange notification，触发 diff.lua

**关键文件**：`lua/codex/diff.lua`、`lua/codex/handlers/diff_apply.lua`

**风险**：multi-file patches、binary files、rejection 后 buffer 状态清理 —— 留出半天 buffer。

### Phase 5 — Approval & Mention 队列 (2d)
- `lua/codex/handlers/approval.lua` — codex 发来 `requestApproval` 时根据 `approval.policy`：
  - `prompt`: 阻塞式 `vim.fn.input` 或 floating prompt 让用户 y/n
  - `auto-deny`: 沿用老行为
  - `auto-allow`: 直接放行
- `lua/codex/init.lua` 中实现 @mention 队列：
  - 已连接 → 50ms debounce 批量推
  - 未连接 → 入队，连接后冲队（10s 超时清空，单条 5s 过期）
  - 顺序发送间隔 25ms

**测试**：mock app_server 推 `requestApproval`，验证三种 policy 行为。

### Phase 6 — 抛光与文档 (2d)
- `lua/codex/logger.lua` — 结构化日志（trace/debug/info/warn/error）
- 错误恢复：app-server 崩溃后自动重启（带退避）
- `PROTOCOL.md` — 记录 codex app-server 协议（哪些 method、哪些 notification、字段含义）
- `ARCHITECTURE.md` — 模块图 + 数据流
- `README.md` — 安装、配置、迁移指南
- 测试覆盖到 80%+

## 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Codex app-server 协议未文档化 | Phase 1-2 延期 | Phase 0 先做 0.5d spike：抓 codex 上游源码 + 抓包，把已知 method/notification 列入 PROTOCOL.md 草稿；不全的部分等遇到再补 |
| 现有用户被命令重命名打断 | 体验回归 | README 顶部"⚠️ Migration"段、deprecated 命令保留 1 个 minor 版本作为 wrapper、命令执行时 `vim.notify` 提示新名 |
| hunk-level diff 实现复杂度 | Phase 4 超时 | 保留 pre-rewrite tag 的 parser（已 tested），仅重写 UI 层与阻塞响应路径 |
| 自实现 WebSocket client 边缘 case | Phase 1 隐藏 bug | 借用 claudecode.nvim 已 production-tested 的 frame parser 与 SHA-1 实现，仅 client handshake 部分自己写 |
| codex app-server "实验性"导致协议变动 | 长期维护成本 | `PROTOCOL.md` 标注插件兼容的 codex 版本范围；CI 加 `codex --version` 检测 |
| 纯 Lua 让代码量翻倍 | Phase 1 比预期长 | 直接复用 claudecode.nvim 的 utils.lua / frame.lua（同 license MIT 兼容）作为起点，而非从零写 |

## 关键复用文件（来自 claudecode.nvim）

> 这些文件可直接借鉴或在尊重 license 前提下移植，避免重复造轮子。

- `claudecode.nvim/lua/claudecode/server/utils.lua` → `codex.nvim/lua/codex/transport/utils.lua`（SHA-1、Base64）
- `claudecode.nvim/lua/claudecode/server/frame.lua` → `codex.nvim/lua/codex/transport/frame.lua`（RFC 6455 frame）
- `claudecode.nvim/lua/claudecode/terminal.lua` + `terminal/*.lua` → 镜像到 `codex.nvim/lua/codex/terminal*`
- `claudecode.nvim/lua/claudecode/selection.lua` → 镜像到 `codex.nvim/lua/codex/selection.lua`
- `claudecode.nvim/lua/claudecode/visual_commands.lua` → 镜像到 `codex.nvim/lua/codex/visual_commands.lua`
- `claudecode.nvim/tests/mocks/vim.lua` → 镜像到 `codex.nvim/tests/mocks/vim.lua`（脱离 Neovim 跑测试）

## 测试策略

- 沿用 busted（zero-dep 版本，不依赖 plenary）
- 自实现 vim API mock（参考 claudecode.nvim/tests/mocks/vim.lua）
- 每个 transport 模块独立 unit 测试（frame 编解码、handshake、tcp connect）
- 集成测试：本地 mock WS server 起在随机端口，覆盖 connect → handshake → ping/pong → RPC → close 全链路
- 端到端 smoke：起真实 `codex app-server`，跑一个 echo prompt，断言收到 progress 事件
- 测试覆盖率目标 80%+

## Verification

每阶段独立验证：

- **Phase 1**: `nvim --headless -c "lua require('codex').start()" -c "qa"` 不报错；mock WS server 测试通过
- **Phase 2**: `:Codex` 切面板可见 + 终端浮起 + `:CodexStop` 干净退出
- **Phase 3**: visual selection → `:'<,'>CodexSend` 后 codex CLI 收到 selection_changed notification（在 codex app-server 日志里能看到）
- **Phase 4**: 让 codex 提一个简单改动 → diff 视图弹出 → `:CodexDiffAccept` → 文件落盘且 codex 收到 FILE_SAVED
- **Phase 5**: 触发 approval 流（如让 codex 跑 `ls`）→ 三种 policy 各自行为正确
- **Phase 6**: README 的 quickstart 跟着走能完整跑通；测试覆盖率达标

最终切换无感测试：让用户在 30 分钟会话里随机切换 claudecode.nvim 与重构后的 codex.nvim，记录体感差异 < 5 处（命令名、UI 反应、配置项查询）。
