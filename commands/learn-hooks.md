---
description: Claude Code Hooks 编写指南
---

# Claude Code Hooks 编写指南

> 面向团队成员的实操手册，从零开始学会配置 Claude Code Hook。
> 前置条件：已安装 Claude Code CLI、jq

---

## 一、Hook 是什么

Hook 是你挂在 Claude Code 生命周期上的「自动脚本」。Claude 每次读文件、改文件、跑命令，都可以在前/后自动触发你写的 shell 命令。

**典型用途：**

| 场景 | 事件 | 效果 |
|------|------|------|
| 改完 .py 自动格式化 | PostToolUse | Claude 改完代码 → ruff 自动格式化 |
| 拦截 `rm -rf` 等危险命令 | PreToolUse | Claude 准备执行 → 检查命令 → 危险就阻止 |
| 保护 .env 不被改写 | PreToolUse | Claude 准备写文件 → 检查路径 → 敏感文件就拒绝 |
| 改完测试文件自动跑测试 | PostToolUse (async) | Claude 改完 → 后台跑 pytest → 不阻塞继续工作 |
| 需要你操作时弹通知 | Notification | 权限弹窗 → macOS 通知弹出 |

---

## 二、从零配置你的第一个 Hook

### 第 1 步：打开配置文件

Hook 配置写在 `settings.json` 里，有三个位置可以放：

| 位置 | 作用域 | 推荐场景 |
|------|--------|---------|
| `~/.claude/settings.json` | **全局**，所有项目生效 | 格式化、危险命令拦截 |
| `项目/.claude/settings.json` | **项目级**，入 git 共享 | 项目特定规则 |
| `项目/.claude/settings.local.json` | **项目级**，不入 git | 个人偏好 |

优先级：local > 项目 > 全局。

打开全局配置：

```bash
# macOS / Linux
code ~/.claude/settings.json
# 或
vim ~/.claude/settings.json
```

### 第 2 步：写配置

在 `settings.json` 中加入 `hooks` 字段。最简示例 — 每次 Claude 改完 .py 文件自动格式化：

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'file=$(jq -r .tool_input.file_path); if [[ \"$file\" == *.py ]]; then ruff format --quiet \"$file\" && ruff check --fix --quiet \"$file\" 2>/dev/null; fi; exit 0'"
          }
        ]
      }
    ]
  }
}
```

### 第 3 步：重启 Claude Code

```bash
# 退出当前会话
/exit

# 重新启动
claude
```

配置修改后**必须重启会话**才生效。

### 第 4 步：验证

让 Claude 随便改一个 .py 文件，观察文件是否被自动格式化。

---

## 三、配置结构详解

```
settings.json
└── hooks
    └── <事件名>                    ← 什么时候触发（如 PostToolUse）
        └── [ 规则组 ]
            ├── matcher: "正则"     ← 过滤条件（如只匹配 Edit|Write）
            └── hooks: [ 动作列表 ]
                └── type: "command" ← 执行什么
                    command: "..."  ← 具体 shell 命令
```

完整字段：

```json
{
  "hooks": {
    "<事件名>": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "你的 shell 命令",
            "timeout": 600,
            "statusMessage": "正在格式化...",
            "async": false
          }
        ]
      }
    ]
  }
}
```

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `matcher` | string | 匹配全部 | 正则过滤（区分大小写） |
| `type` | string | — | `"command"` / `"prompt"` / `"agent"` |
| `command` | string | — | shell 命令（type=command 时必填） |
| `timeout` | number | 600 | 超时秒数 |
| `statusMessage` | string | — | 执行时的 spinner 提示 |
| `async` | boolean | false | true = 后台执行不阻塞 |

---

## 四、核心概念：事件、数据、退出码

### 4.1 常用事件（只列最常用的 5 个）

| 事件 | 什么时候触发 | matcher 匹配什么 | 能阻止 Claude 吗 |
|------|------------|-----------------|-----------------|
| **PreToolUse** | 工具执行**前** | 工具名 | ✅ exit 2 阻止 |
| **PostToolUse** | 工具执行**后** | 工具名 | ❌ 已经执行完了 |
| **Notification** | 弹通知时 | 通知类型 | ❌ |
| **Stop** | Claude 结束响应 | — | ✅ exit 2 让它继续 |
| **SessionStart** | 会话启动时 | startup/resume | ❌ |

全部 18 种事件见附录。

### 4.2 Hook 怎么拿到数据

**Hook 通过 stdin 接收 JSON，用 `jq` 提取。** 不是环境变量！

```bash
# ✅ 正确 — 从 stdin 读 JSON
file=$(jq -r '.tool_input.file_path')

# ❌ 错误 — 这个环境变量不存在
file="$CLAUDE_FILE_PATH"
```

PostToolUse 收到的完整 JSON：

```json
{
  "session_id": "abc123",
  "cwd": "/Users/you/project",
  "hook_event_name": "PostToolUse",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/Users/you/project/main.py",
    "old_string": "...",
    "new_string": "..."
  },
  "tool_response": { "success": true }
}
```

**不同工具的 `tool_input` 字段不同：**

| 工具 | 关键字段 |
|------|---------|
| Edit | `file_path`, `old_string`, `new_string` |
| Write | `file_path`, `content` |
| Bash | `command`, `description` |
| Read | `file_path` |
| Glob | `pattern`, `path` |

**可用的环境变量（只有这几个）：**

| 变量 | 说明 |
|------|------|
| `$CLAUDE_PROJECT_DIR` | 项目根目录 |
| `$CLAUDE_ENV_FILE` | 环境变量文件（仅 SessionStart） |

### 4.3 退出码决定行为

```
exit 0   →  放行，一切正常
exit 2   →  阻塞！Claude 被拦截，stderr 内容作为错误反馈
exit 其他 →  忽略，不阻塞也不报错
```

**记住：只有 `exit 2` 能阻止 Claude，且只在 PreToolUse / UserPromptSubmit / Stop 等支持阻塞的事件上有效。PostToolUse 不能阻塞（已经执行完了）。**

---

## 五、编写 Hook 的标准流程

### 步骤 1：确定需求

先回答三个问题：

```
1. 我想在什么时候触发？    → 选事件（PreToolUse / PostToolUse / ...）
2. 我想在哪些工具触发？    → 写 matcher（"Edit|Write" / "Bash" / ...）
3. 我想做什么？           → 写 command
```

### 步骤 2：写内联命令或脚本

**简单逻辑 → 内联命令：**

```json
"command": "bash -c '...一行命令...'"
```

**复杂逻辑 → 独立脚本文件：**

```json
"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/my-hook.sh"
```

脚本文件记得加执行权限：

```bash
chmod +x .claude/hooks/my-hook.sh
```

### 步骤 3：编写命令的模板

不管做什么，命令的结构都是这样：

```bash
bash -c '
  # 1. 从 stdin 提取需要的数据
  file=$(jq -r .tool_input.file_path)

  # 2. 判断是否需要处理
  if [[ 条件 ]]; then

    # 3. 执行你的逻辑
    做什么...

  fi

  # 4. 始终 exit 0（除非你要阻塞）
  exit 0
'
```

### 步骤 4：测试

1. 写好配置 → 重启 Claude Code
2. 让 Claude 触发对应操作
3. 检查结果

---

## 六、团队常用 Hook 配方（复制即用）

### 配方 1：Python 自动格式化 + lint 修复

> 每次 Claude 修改 .py 文件后，自动用 ruff 格式化并修复 lint 问题。

**前置：** `uv tool install ruff`（确认 `which ruff` 有输出）

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'file=$(jq -r .tool_input.file_path); if [[ \"$file\" == *.py ]]; then ruff format --quiet \"$file\" && ruff check --fix --quiet \"$file\" 2>/dev/null; fi; exit 0'"
          }
        ]
      }
    ]
  }
}
```

**⚠️ 注意：** ruff 的路径在 hook 环境中可能找不到，用 `which ruff` 拿到绝对路径，替换命令中的 `ruff`。例如：`/Users/你的用户名/.local/bin/ruff`

---

### 配方 2：拦截危险 Bash 命令

> Claude 执行 Bash 命令前检查，包含 `rm -rf`、`DROP TABLE`、`TRUNCATE` 等关键词时直接阻止。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'cmd=$(jq -r .tool_input.command); if echo \"$cmd\" | grep -qiE \"rm -rf /|drop table|truncate|mkfs|dd if=|:(){ :|:& };:\"; then echo \"危险命令被拦截: $cmd\" >&2; exit 2; fi; exit 0'"
          }
        ]
      }
    ]
  }
}
```

---

### 配方 3：保护敏感文件

> 禁止 Claude 修改 `.env`、`uv.lock`、`package-lock.json` 等文件。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'file=$(jq -r .tool_input.file_path); for p in .env uv.lock package-lock.json; do if [[ \"$file\" == *\"$p\" ]]; then echo \"保护文件不可修改: $file\" >&2; exit 2; fi; done; exit 0'"
          }
        ]
      }
    ]
  }
}
```

---

### 配方 4：macOS 桌面通知

> Claude 需要你操作时弹出系统通知，不用一直盯着终端。

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code 需要你的注意\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

---

### 配方 5：修改测试文件后自动跑 pytest

> 后台异步执行，不阻塞 Claude 继续工作。

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'file=$(jq -r .tool_input.file_path); if [[ \"$file\" == *_test.py ]] || [[ \"$file\" == *test_*.py ]]; then cd \"$CLAUDE_PROJECT_DIR\" && python -m pytest \"$file\" -x -q; fi; exit 0'",
            "async": true,
            "timeout": 300
          }
        ]
      }
    ]
  }
}
```

---

### 配方 6：多语言格式化（脚本文件版）

> 根据文件后缀自动选择格式化工具。适合前后端混合项目。

**配置（`.claude/settings.json`）：**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format.sh"
          }
        ]
      }
    ]
  }
}
```

**脚本（`.claude/hooks/format.sh`）：**

```bash
#!/bin/bash
FILE_PATH=$(jq -r '.tool_input.file_path')

case "$FILE_PATH" in
  *.py)
    ruff format --quiet "$FILE_PATH"
    ruff check --fix --quiet "$FILE_PATH" 2>/dev/null
    ;;
  *.js|*.ts|*.jsx|*.tsx)
    npx prettier --write "$FILE_PATH" 2>/dev/null
    ;;
  *.go)
    gofmt -w "$FILE_PATH"
    ;;
  *.java)
    google-java-format -i "$FILE_PATH" 2>/dev/null
    ;;
esac

exit 0
```

```bash
chmod +x .claude/hooks/format.sh
```

---

### 配方 7：组合多个 Hook

> 一个事件可以挂多个规则组，不同 matcher 触发不同动作。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'cmd=$(jq -r .tool_input.command); if echo \"$cmd\" | grep -qE \"rm -rf /\"; then echo \"拦截\" >&2; exit 2; fi; exit 0'"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'file=$(jq -r .tool_input.file_path); if [[ \"$file\" == *.env ]]; then echo \"保护\" >&2; exit 2; fi; exit 0'"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'file=$(jq -r .tool_input.file_path); if [[ \"$file\" == *.py ]]; then ruff format --quiet \"$file\"; fi; exit 0'"
          }
        ]
      }
    ]
  }
}
```

---

## 七、踩坑清单

| # | 坑 | 怎么避免 |
|---|----|---------|
| 1 | 用 `$CLAUDE_FILE_PATH` 取文件路径 | ❌ 不存在。用 `jq -r .tool_input.file_path` 从 stdin 读 |
| 2 | 配置改完没重启 | 改 `settings.json` 后必须重启 Claude Code 会话 |
| 3 | hook 里 `ruff` 命令找不到 | hook 的 shell 没有完整 PATH，用 `which ruff` 拿绝对路径 |
| 4 | `~/.bashrc` 有 echo 导致 JSON 解析失败 | 把 echo 包在 `if [[ $- == *i* ]]` 里，只在交互 shell 执行 |
| 5 | PostToolUse 里 exit 2 想阻止操作 | ❌ 不能阻止，文件已经改了。要阻止用 PreToolUse |
| 6 | Stop hook 死循环 | 检查 `stop_hook_active`，为 true 时直接 `exit 0` |
| 7 | matcher 写了小写 `bash` | 区分大小写，工具名是 `Bash`、`Edit`、`Write` |
| 8 | 命令中引号嵌套出错 | 复杂逻辑用独立 `.sh` 脚本文件，别硬塞一行 |

---

## 附录：全部 18 种事件

| 事件 | 触发时机 | matcher 匹配 | 能阻塞 |
|------|---------|-------------|--------|
| `SessionStart` | 会话启动/恢复 | startup / resume / clear / compact | 否 |
| `SessionEnd` | 会话结束 | clear / logout / prompt_input_exit | 否 |
| `UserPromptSubmit` | 用户提交提示词 | — | 是 |
| `PreToolUse` | 工具执行前 | 工具名 | 是 |
| `PostToolUse` | 工具成功后 | 工具名 | 否 |
| `PostToolUseFailure` | 工具失败后 | 工具名 | 否 |
| `PermissionRequest` | 权限弹窗 | 工具名 | 是 |
| `Notification` | 通知发出 | 通知类型 | 否 |
| `Stop` | 主代理结束 | — | 是 |
| `SubagentStart` | 子代理启动 | 代理类型 | 否 |
| `SubagentStop` | 子代理结束 | 代理类型 | 是 |
| `TeammateIdle` | 团队成员空闲 | — | 是 |
| `TaskCompleted` | 任务完成 | — | 是 |
| `ConfigChange` | 配置变更 | 配置来源 | 是 |
| `WorktreeCreate` | 工作树创建 | — | 是 |
| `WorktreeRemove` | 工作树删除 | — | 否 |
| `PreCompact` | 上下文压缩前 | manual / auto | 否 |
