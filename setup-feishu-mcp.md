为当前 Claude Code 环境接入飞书 MCP Server，实现直接读写飞书多维表格（Bitable）。

## 前置条件

- Node.js >= 20
- 飞书开放平台应用（App ID + App Secret）

## 执行流程

### 第 1 步：收集凭据

向用户确认以下信息：

1. **App ID**：飞书应用的 App ID（格式 `cli_xxxx`）
2. **App Secret**：飞书应用的 App Secret
3. **工具集范围**：
   - `preset.base.default` — 仅多维表格（推荐，token 消耗少）
   - `preset.default` — 全部功能（文档、消息、日历、多维表格）
   - `preset.im.default` — 即时通讯
   - `preset.calendar.default` — 日历管理
   - `preset.light` — 轻量工具集
4. **作用范围**：
   - `user` — 用户级别，所有项目可用（推荐）
   - `project` — 仅当前项目可用

如果用户未提供工具集和范围，默认使用 `preset.base.default` + `user`。

### 第 2 步：检查环境

```bash
# 检查 Node.js 版本（需要 >= 20）
node --version

# 检查是否已有飞书 MCP 配置
claude mcp get lark-mcp
```

如果已存在 lark-mcp 配置，提示用户是否覆盖。

### 第 3 步：添加 MCP Server

使用 `claude mcp add-json` 命令添加（不要手动编辑配置文件）：

```bash
claude mcp add-json lark-mcp '{
  "command": "npx",
  "args": [
    "-y",
    "@larksuiteoapi/lark-mcp",
    "mcp",
    "-a", "{用户的APP_ID}",
    "-s", "{用户的APP_SECRET}",
    "-t", "{选择的工具集}"
  ]
}' --scope {选择的范围}
```

### 第 4 步：指导用户开通飞书权限

告知用户需要在飞书开放平台完成以下操作：

1. **开通权限**：访问以下链接开通多维表格权限
   ```
   https://open.feishu.cn/app/{APP_ID}/auth?q=bitable:app:readonly,bitable:app,base:table:read&op_from=openapi&token_type=tenant
   ```
   推荐开通 `bitable:app`（读写权限）

2. **发布应用版本**：开通权限后必须发布新版本才生效
   - 应用管理后台 → 版本管理与发布 → 创建版本 → 申请发布

3. **添加文档应用**：打开目标多维表格 → 右上角「...」→「更多」→「添加文档应用」→ 搜索并添加应用

### 第 5 步：验证连接

提示用户：
1. 完全退出 Claude Code（`/exit` 或 `Ctrl+C`）
2. 重新启动 Claude Code
3. 用 `/mcp` 查看 lark-mcp 是否加载成功
4. 提供一个多维表格链接进行测试读取

### 第 6 步：测试读取

用户提供多维表格链接后，从 URL 中提取 `app_token`：
```
https://xxx.feishu.cn/base/{app_token}?table={table_id}&view={view_id}
```

依次调用：
1. `bitable_v1_appTable_list` — 列出数据表
2. `bitable_v1_appTableField_list` — 查看字段结构
3. `bitable_v1_appTableRecord_search` — 读取记录

将结果格式化展示给用户，确认连接成功。

## 常见问题处理

### 报错 99991672
权限未开通。引导用户回到第 4 步开通权限并发布版本。

### MCP 工具未加载
确认用 `claude mcp add-json` 命令添加，而非手动编辑 `mcp.json`，然后重启 Claude Code。

### Token 超限
工具集太大导致 token 超限，建议切换为 `preset.base.default` 或 `preset.light`。

### 没有"列出所有多维表格"的接口
飞书 API 不提供此接口。用户需从多维表格 URL 中获取 `app_token`。如需搜索文档，将工具集切换为 `preset.default`。

## 守护栏

- 不在命令输出中明文展示 App Secret（展示时用 `***` 遮掩后半段）
- 使用 `claude mcp add-json` 命令添加，不手动编写配置文件
- 不擅自选择工具集范围，必须与用户确认
- 每步执行完毕后等用户确认再进行下一步
