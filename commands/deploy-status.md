---
description: 实拉 W230 上某个 v5 待部署项目的部署现状，输出运行前信息表（代码位置/分支/commit/环境/读写库/运行记录/调度状态）
argument-hint: dataupdate | fm-py | riskmodel-py | v4-optimizer30-py | v4-oss-update-rank | v4-demo-fund-etl | v4-trading-new | v4-tracking-new | email-downloader | v4-email-download-230
allowed-tools: Bash, Read, Edit, Write
---

分析 **`$ARGUMENTS`** 在 W230 上的部署现状，输出一张运行前信息表。

## 项目范围（只接受这 10 个）

`dataupdate`、`fm-py`、`riskmodel-py`、`v4-optimizer30-py`、`v4-oss-update-rank`、`v4-demo-fund-etl`、`v4-trading-new`、`v4-tracking-new`、`email-downloader`、`v4-email-download-230`

若 `$ARGUMENTS` 为空或不在此列表，列出这 10 个让用户选，不要猜。

⚠️ `email-downloader` 在 W230 上是 **非 git 手工部署**（`D:\email-downloader`），`git` 那几项一律填 `⚠️ 非 git`，改报目录大小与 `.env` 是否存在。

## 铁律

- **一切数据必须实拉，禁止凭记忆或凭台账填表。** 台账可能已过期。
- **禁止打印口令**。读 env 文件时只输出键名，值一律打码（`PASSWORD` / `WEBHOOK` / `SECRET` / `TOKEN` 类键）。
- 拿不到的项写 `🟡 未取到` 并说明原因，**不要留空、不要编**。

## 环境事实（W230）

| 项 | 值 |
|---|---|
| SSH | `ssh -p 47044 qw@9kfhg3026522.vicp.fun` |
| git | **不在 PATH**，必须用全路径 `E:\ProgramFiles\Git\cmd\git.exe` |
| v5 代码根 | `D:\00-v5-latest-code\<项目名>` |
| v4 生产根 | `D:\00-v4-latest-code\<项目名>`（可能存在旧的重复 checkout，要一并检查并指出） |
| 部署口径 | v5 统一部署 **`dev`** 分支；写 RDS01 的 `_mh` 后缀隔离库，MySQL 账号 `mh` |
| 配置目录 | `C:\Users\qw\.config\optimizer30\`（**目录名叫 optimizer30 是历史遗留，不是笔误**） |
| 状态/日志根 | `D:\dev\<项目>-state\`、`D:\dev\<项目>-logs\`（各项目命名可能不同，先探） |

## Windows SSH 踩坑（务必遵守，否则白跑）

1. **PowerShell 脚本里不要写中文字符串** —— GBK 解码会截断，报 `TerminatorExpectedAtEndOfString`。
2. **复杂命令写成 `.ps1` 上传执行**，不要在 ssh 命令行里嵌套引号。上传用：本地 `base64` → `scp` 到 `C:\Users\qw\x.b64` → 远端 `[Convert]::FromBase64String` 写文件。**base64 直接塞进命令行会超长度限制。**
3. 读中文日志加 `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8`，否则整片乱码。
4. `@{u}` 会被 PowerShell 当 hashtable，查上游差距要写 `origin/<branch>`。
5. 长任务（`fetch` / `preflight`）放后台并把输出重定向到远端文件再读，避免 2 分钟超时。

## 采集项

按下表逐项采，命令给的是 `dataupdate` 示例，换项目名即可。

| 项 | 怎么拿 |
|---|---|
| 机器 | 固定 `W230（DESKTOP-IU66O6O）` |
| 代码位置 | 探 `D:\00-v5-latest-code\<项目>` 是否存在；**同时**探 v4 生产根有无重复 checkout |
| 分支 | `git -C <dir> rev-parse --abbrev-ref HEAD`，并标注是否 = `dev`（口径要求） |
| 最新 commit | `git -C <dir> log -1 --format='%h\|%an <%ae>\|%ad\|%s' --date=iso` |
| 与 origin/dev 差距 | `git -C <dir> fetch origin` 后 `rev-list --count HEAD..origin/dev` |
| 工作区 | `git -C <dir> status --porcelain`（空=干净；标出是否有已跟踪文件被改） |
| 拉码方式 | `git -C <dir> config --get remote.origin.url`；裸 `git@github.com:` = **无可用 key、拉不动**（W230 无默认 key），别名 `github.com-xxx` = 已配专用 deploy key |
| 环境 | `.venv\Scripts\python.exe --version`；有 `uv.lock` 则报是否 `uv sync` 过 |
| 离线验收 | 有 `scripts\preflight.py` 就跑 `--profile full`，报 `passed/failed` |
| 配置目录 | 列 `C:\Users\qw\.config\optimizer30\` 的文件名+修改时间；**核对键面是否齐全**（比对仓库内 `config/env/*.example` 的键名，只比键不比值） |
| 读 / 写 | 从 env 的 `*_DATABASE` / `*_NAME` / `APPROVED_*_ENDPOINTS` 提取库名；确认写目标是 `_mh` 隔离库而非生产 `_hg` |
| 运行记录 | 遍历 `D:\dev\<项目>-state\receipts\*\*\closeout.json`，取 `run_id` / `snapshot_date` / `failure_stage` / `budget.outcome` / `elapsed_seconds` |
| **调度状态** | `Get-ScheduledTask` 过滤 Actions 含项目名 —— **没有计划任务就是"手工触发"，必须明确指出** |
| 飞书通知 | 探 `D:\dev\<项目>-state\feishu_webhook.txt` 是否存在；仓库有 `notify_feishu.py` 则说明触发条件 |
| 日志 | 列 `D:\dev\<项目>-logs\` 最近 3 个文件名 |
| 启动命令 | 从 `scripts\win\run_daily.ps1`（或等价 wrapper）的实际参数列表推导**可直接粘贴执行**的完整命令，含必需的环境变量 |

## 输出格式

先出主表，再出运行记录表，再出启动命令，最后列未闭合问题。

```
# <项目> 运行现状（<分支>）

| 项 | 值 |
|---|---|
| 机器 / 代码位置 / 分支 / 最新 commit / 提交人 / 提交日期 |
| 与 origin/dev 差距 / 工作区 / 拉码方式 / 环境 / 离线验收 |
| 配置目录 / 读 / 写 / 调度方式 / 飞书通知 / 日志 |

## 运行记录
| target | run_id | 失败段 | 预算 | 耗时 |

## 当前的运行方式
（可粘贴执行的完整命令）

## 仍未闭合的问题
（逐条，标 🔴/⚠️，写清是数据问题、配置问题还是代码问题）
```

## 判读要求

不要只罗列数字，要给出判断：

- 分支 ≠ `dev` → 🔴 不符合部署口径
- remote 是裸 `git@github.com:` → 🔴 拉不动，需配 deploy key
- 无计划任务 → 🔴 未真正上线，靠人工触发
- 写目标含 `_hg` → 🔴 可能污染生产库
- v4 生产根有重复 checkout → ⚠️ 指出待清理
- `closeout.json` 的 `failure_stage` 为空但退出码非 0 → 说明是**发布后自检**失败，已发布数据不受影响，别混为一谈
- `deadline_overdue` 只是超软预算，不是失败，要讲清

## 维护台账

采完后询问用户是否把结论同步进 `资产/D_04_W146部署计划.md` 对应项。**未经用户确认不要改其他文件。**
