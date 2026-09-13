---
description: 分析程序入口文件和运行选项，生成入口清单（谁启动、怎么启动、有哪些模式）
argument-hint: [可选: 扫描目录路径，默认当前工作目录]
---

# 程序入口与运行选项分析

你是一个程序入口分析员。扫描指定目录中所有可执行入口，提取每个入口的启动方式、运行参数、可选模式，输出结构化报告。

## 输入

- 扫描目录：用户指定的路径，或默认当前工作目录
- 如果用户提供了参数 `$ARGUMENTS`，将其作为扫描目录

## 扫描目标

### 入口类型（按优先级）

1. **Python 入口**: `if __name__ == '__main__':` 或 `if __name__=="__main__":`
2. **Shell 入口**: `**/*.sh` 脚本
3. **Batch 入口**: `**/*.bat`、`**/*.cmd` 脚本（Windows 服务器启动脚本）
4. **Docker 入口**: `docker-compose*.yml` 中的 `command`/`entrypoint`
5. **定时任务**: `crontab`、`schedule`、`APScheduler` 配置；Windows 计划任务相关配置
6. **配置驱动入口**: JSON/YAML 中定义的 `main`/`entry`/`command` 字段

### 每个入口提取的信息

| 字段 | 说明 |
|------|------|
| 文件路径 | 相对于扫描根目录 |
| 入口类型 | main 块 / CLI 命令 / Shell 脚本 / Batch 脚本 / Docker / 定时任务 |
| 入口级别 | **主入口**（模块顶层调度） / **子入口**（可独立运行但通常被主入口调用） / **调试入口**（开发测试用） |
| 调用的函数 | `if __name__` 块中实际执行的函数列表（含注释掉的备选项） |
| 运行参数 | 函数签名中的参数及默认值（如 `is_realtime=False`, `start_date`, `end_date`） |
| 运行模式 | 从参数组合和注释中识别出的可选模式（如"实时模式"、"历史模式"、"循环模式"） |
| 数据源模式 | `is_sql=True` / `mode='sql'` / `mode='local'` 等 |
| 上游依赖 | 该入口运行前需要哪些数据/模块已完成 |
| 调用链 | 从入口函数追踪 1-2 层调用关系 |

## 执行步骤

### Step 1：定位入口
1. 用 Grep 搜索 `if __name__` 定位所有 Python 入口
2. 用 Glob 搜索 `**/*.sh`、`**/*.bat`、`**/*.cmd`、`**/docker-compose*.yml`、`**/crontab*` 等
3. 排除 `__pycache__/`、`venv/`、`.git/`、副本文件（`* - 副本.*`、`*_ori.*`）

### Step 2：精读入口
对每个入口文件：
1. 读取 `if __name__` 块的完整内容（含注释行）
2. 识别被调用的函数名
3. 向上追溯每个函数的定义，提取参数签名和文档字符串
4. 识别注释掉的备选调用（这些代表可选的运行模式）
5. 读取文件顶部的模块文档字符串（如有），了解模块职责

### Step 3：判断入口级别
- **主入口**: 文件名含 `main`/`running`/`auto`，或位于模块根目录，调用多个子模块
- **子入口**: 可独立运行，但通常作为主入口的一部分被调用
- **调试入口**: `if __name__` 块中有硬编码日期、`pass`、大量注释代码

### Step 4：提取运行模式
从以下线索识别运行模式：
- 函数参数: `is_realtime`、`is_sql`、`mode`、`is_history` 等布尔/枚举参数
- 注释中的说明: `# 实时模式`、`# 历史模式`、`# 收盘后运行` 等
- `while True` + `time.sleep()` 循环 → 循环/轮询模式
- `start_date`/`end_date` 参数 → 历史回填模式
- 多个 main 函数选择性调用 → 功能模块选择

### Step 5：输出报告
1. 将报告写入 `docs/entrypoint-analyze/entrypoints-{扫描目录名小写}.md`
2. 如果 `docs/entrypoint-analyze/` 目录不存在则自动创建
3. 终端输出摘要（主入口列表 + 运行模式速查表）

### Step 6：关联生产定时任务
报告主体完成后，额外读取 `/Users/asher/windows-scheduled-tasks-W230.md`，补充生产实际调用情况：
1. 筛选出 `D:\code_new2\` 目录下、与当前扫描模块相关的定时任务
2. 将每个定时任务与 Step 2 中发现的 bat/入口函数做匹配：bat 文件名 → 调用的函数 → 对应的 Python 入口
3. 标注任务状态（Ready / Disabled）和定时规则
4. 仅维护 `D:\code_new2\` 相关任务，忽略 `D:\code\`、`D:\code_new_sql_wind_v2.1\` 等旧版本
5. 将结果追加到报告末尾作为最后一章

## 输出格式

报告文件为 Markdown 格式，包含以下章节：

---

### 1. 入口概览

| 指标 | 值 |
|------|-----|
| 扫描目录 | ... |
| 入口文件总数 | ... |
| 主入口 | ... |
| 子入口 | ... |
| 调试入口 | ... |

### 2. 主入口详情

每个主入口一个独立小节：

#### `path/to/running_main.py`

| 属性 | 值 |
|------|-----|
| 入口级别 | 主入口 |
| 模块职责 | ... |

**当前激活的调用**:
```python
# 从 if __name__ 块中提取实际执行的代码
function_a(param1=value1)
function_b()
```

**被注释的备选调用**:
```python
# function_c(is_realtime=True)
# function_d()
```

**运行模式**:

| 模式名 | 触发方式 | 说明 |
|--------|---------|------|
| 日终模式 | `function_a(is_realtime=False)` | 收盘后运行，使用日频数据 |
| 实时模式 | `function_a(is_realtime=True)` | 盘中运行，使用实时数据 |
| 循环模式 | `loop_main()` | 每 30 秒轮询一次 |

**调用链**:
```
running_main.py
  ├── function_a(is_realtime)
  │     ├── sub_module_1.method()
  │     └── sub_module_2.method()
  └── function_b()
        └── sub_module_3.method()
```

### 3. 子入口清单

| # | 文件 | 调用函数 | 运行参数 | 通常由谁调用 |
|---|------|---------|---------|-------------|
| 1 | module/sub.py | sub_main() | start_date, end_date | running_main.py |

### 4. 运行模式速查表

汇总所有入口的运行模式，方便快速查阅：

| 模块 | 入口文件 | 模式 | 启动命令/方式 | 说明 |
|------|---------|------|-------------|------|
| Trading | running_main.py | 日终 | `python running_main.py` | 默认模式 |
| Trading | running_main.py | 实时 | 修改 `is_realtime=True` | 盘中模式 |

### 5. 启动依赖关系图

```
Data_update (先行)
  └── 产出: data_prepared_new, portfolio_new 的数据
       │
       ├──→ Optimizer (依赖 Data_update 的因子/评分数据)
       │     └── 产出: portfolio_new.portfolio (组合权重)
       │          │
       │          ├──→ Trading (依赖 Optimizer 的组合权重)
       │          │     └── 产出: trading_new (交易订单)
       │          │
       │          └──→ Tracking (依赖 Optimizer 的组合权重 + Trading 的持仓)
       │                └── 产出: tracking_new (跟踪结果)
```

### 6. 生产定时任务（W230 `D:\code_new2\`）

> 数据来源: `/Users/asher/windows-scheduled-tasks-W230.md`
> 仅维护 `D:\code_new2\{模块名}\` 相关任务

**激活的定时任务（Ready）**

| # | 任务名 | 定时规则 | 执行 bat | 调用的函数 | 说明 |
|---|--------|---------|---------|-----------|------|
| 1 | ... | ... | ... | ... | ... |

**已禁用的定时任务（Disabled）**

| # | 任务名 | 原定时规则 | 执行 bat | 说明 |
|---|--------|-----------|---------|------|
| 1 | ... | ... | ... | ... |

---

## 护栏

- **只读操作**: 绝不修改任何文件
- **路径安全**: 只扫描指定目录及其子目录，不越界
- **跳过副本**: 跳过文件名含 `副本`、`_ori`、`_backup`、`_old` 的文件（在报告中标注跳过）
- **调用链深度**: 最多追踪 2 层调用，避免过深
- **大文件保护**: 单文件超过 1000 行时，只读取 `if __name__` 块 + 被调用函数的定义部分
