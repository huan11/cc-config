---
description: 映射每个程序入口到其最终的数据库读写，生成「入口 → DB」端到端数据流图，方便验收
argument-hint: [可选: 扫描目录路径，默认当前工作目录]
---

# 入口 → 数据库 映射分析

你是一个数据流追踪员。你的任务是：**从每个程序入口出发，沿调用链追踪到它最终读写了哪些数据库表**，生成一张「入口 → DB」的端到端映射表。

这张表的核心价值是**验收**：运行入口 X 后，去查表 A、B、C 是否有预期数据。

## 输入

- 扫描目录：用户指定的路径，或默认当前工作目录
- 如果用户提供了参数 `$ARGUMENTS`，将其作为扫描目录

## 与已有分析的关系

本命令结合了 `analyze-entrypoints`（入口发现）和 `analyze-db-connections`（DB 连接发现）的能力，但核心价值在于**把两者串起来**——建立入口到 DB 操作的因果链。

如果 `docs/` 目录下已存在以下文件，**优先读取复用**，跳过对应的发现阶段：
- `docs/entrypoint-analyze/entrypoints-*.md` → 复用入口清单
- `docs/db-connections-*.md` → 复用 DB 连接清单

如果不存在，则自行发现（精简版，不生成独立报告）。

## 执行步骤

### Step 1：发现入口

**如果已有入口分析报告**：读取并提取入口清单（文件路径、入口级别、调用函数）。

**如果没有**：快速扫描：
1. Grep 搜索 `if __name__` 定位 Python 入口
2. Glob 搜索 `**/*.sh`、`**/*.bat`、`**/*.cmd`
3. 排除 `__pycache__/`、`venv/`、`.git/`、副本文件
4. 对每个入口，读取 `if __name__` 块，提取调用的函数名

### Step 2：发现 DB 连接

**如果已有 DB 连接报告**：读取并提取连接配置（Host、Port、Database、表名、方向）。

**如果没有**：快速扫描：
1. 搜索连接字符串：`mysql+pymysql://`、`create_engine`、`pymysql.connect`、`DB_HOST` 等
2. 搜索 SQL 配置文件：`*_sql.yaml`、`*_path_config.json`
3. 提取 Host、Port、Database、表名、读写方向

### Step 3：追踪调用链（核心步骤）

对**每个主入口和子入口**：

1. 读取入口的 `if __name__` 块，确认调用的顶层函数
2. 追踪顶层函数的定义，识别它调用的下一层函数（最多追踪 **3 层**）
3. 在调用链中搜索以下 DB 操作模式：

**写入模式（Output）**：
- `df.to_sql` / `to_sql(` — 提取目标表名
- `cursor.execute(INSERT` / `cursor.execute(UPDATE` / `cursor.execute(DELETE`
- `sqlSaving_main` / `sql_saving` — 追踪其配置文件（`*_sql.yaml`）找目标表
- `session.commit()` / `.save()` / `.create()`
- `pd.DataFrame.to_sql`

**读取模式（Input）**：
- `pd.read_sql` / `read_sql(` — 提取 SQL 中的表名
- `cursor.execute(SELECT` — 提取 FROM 后的表名
- `global_dic.get(` — 追踪 `*_path_config.json` 找源表
- `session.query(` / `.filter(` / `.all()`

**配置驱动的 DB 操作**：
- 如果函数加载了 `*_sql.yaml`，解析 YAML 找到所有目标表
- 如果函数加载了 `*_path_config.json`，解析 JSON 的 `sub_folder` 找到所有源表

4. 对于间接调用（函数 A 调用模块 B 的函数），跨文件追踪 import 链

### Step 4：构建映射

将 Step 3 的追踪结果汇总为映射表：

```
入口文件 → 调用链 → [Input] 源表清单 + [Output] 目标表清单
```

每条映射记录包含：
| 字段 | 说明 |
|------|------|
| 入口文件 | 入口的相对路径 |
| 入口级别 | 主入口 / 子入口 |
| 调用链摘要 | 入口 → func_a → func_b → DB操作（简化到关键节点） |
| DB 实例 | Host:Port |
| Database | 数据库名 |
| 表名 | 具体表名 |
| 方向 | Input / Output |
| 操作方式 | to_sql / read_sql / sqlSaving_main / cursor.execute 等 |
| 代码位置 | `file.py:line` — 实际执行 DB 操作的代码行 |

### Step 5：交叉验证

1. 检查是否有 DB 连接在任何入口的调用链中都没出现（**孤立连接**）
2. 检查是否有入口没有任何 DB 操作（**纯计算入口** 或分析遗漏）
3. 检查同一张表是否被多个入口写入（**写入冲突风险**）

### Step 6：生成验收清单

基于映射结果，自动生成每个入口的验收要点：

```
运行入口 X 后，检查：
  ✅ [Output] database_a.table_1 — 应有新增/更新记录
  ✅ [Output] database_a.table_2 — 应有新增/更新记录
  ⬅️ [Input]  database_b.table_3 — 运行前需确保有数据
```

### Step 7：输出报告

1. 将报告写入 `docs/entry-to-db-map-{扫描目录名小写}.md`
2. 如果 `docs/` 目录不存在则自动创建
3. 终端输出摘要（映射总览 + 验收清单）

## 输出格式

报告文件为 Markdown 格式，包含以下章节：

---

### 1. 分析概览

| 指标 | 值 |
|------|-----|
| 扫描目录 | ... |
| 分析日期 | YYYY-MM-DD HH:MM |
| 入口数（主/子） | N 个主入口 + M 个子入口 |
| 涉及 DB 实例 | N 个 |
| 涉及数据库 | N 个 |
| 涉及表 | N 个（读 X / 写 Y） |
| 复用已有报告 | entrypoints-xxx.md / db-connections-xxx.md / 无 |

### 2. 入口 → DB 映射总览

一张大表，快速看清全局：

| # | 入口文件 | 级别 | 读取的表 | 写入的表 |
|---|---------|------|---------|---------|
| 1 | running_main.py | 主入口 | db_a.t1, db_a.t2 | db_b.t3, db_b.t4 |
| 2 | sub_module.py | 子入口 | db_a.t1 | db_b.t3 |

### 3. 逐入口详细映射

每个入口一个小节：

#### E-01: `running_main.py`（主入口）

**调用链：**
```
running_main.py
  └── main_function()                    # running_main.py:50
        ├── prepare_data()               # module_a.py:20
        │     └── [Input] pd.read_sql    → db_a.table_1    # module_a.py:35
        ├── calculate()                  # module_b.py:10
        │     └── [Input] global_dic.get → db_a.table_2    # module_b.py:22
        └── save_result()               # module_c.py:5
              └── [Output] to_sql        → db_b.table_3    # module_c.py:18
```

**DB 操作清单：**

| # | 方向 | DB 实例 | Database | 表名 | 操作方式 | 代码位置 |
|---|------|--------|----------|------|---------|---------|
| 1 | Input | host1:3306 | db_a | table_1 | pd.read_sql | module_a.py:35 |
| 2 | Input | host1:3306 | db_a | table_2 | global_dic.get | module_b.py:22 |
| 3 | Output | host2:3306 | db_b | table_3 | to_sql | module_c.py:18 |

---

### 4. 数据库视角（反向映射）

从 DB 表的角度看哪些入口在操作它：

#### `host1:3306` — db_a

| 表名 | 读取者 | 写入者 |
|------|--------|--------|
| table_1 | running_main.py, sub_a.py | - |
| table_2 | running_main.py | data_update.py |

#### `host2:3306` — db_b

| 表名 | 读取者 | 写入者 |
|------|--------|--------|
| table_3 | tracking.py | running_main.py, sub_b.py |

### 5. 交叉验证

**孤立连接**（配置中存在但未被任何入口使用）：
| DB 实例 | Database | 来源文件 | 可能原因 |
|--------|----------|---------|---------|
| ... | ... | ... | 废弃配置 / 分析遗漏 |

**写入冲突**（同一张表被多个入口写入）：
| 表名 | 写入入口 | 风险说明 |
|------|---------|---------|
| db_b.table_3 | entry_a.py, entry_b.py | 并发运行可能数据冲突 |

**无 DB 操作的入口**：
| 入口文件 | 可能原因 |
|---------|---------|
| debug_tool.py | 调试入口 / 纯计算 |

### 6. 验收清单

按入口分组，每个入口列出验收要点：

#### E-01: `running_main.py`

**运行前置条件（Input 依赖）：**
- [ ] `host1:3306/db_a.table_1` — 需有数据（被 `module_a.py:35` 读取）
- [ ] `host1:3306/db_a.table_2` — 需有数据（被 `module_b.py:22` 读取）

**运行后检查点（Output 验证）：**
- [ ] `host2:3306/db_b.table_3` — 应有新增/更新记录（由 `module_c.py:18` 写入）

#### E-02: `sub_module.py`
...

### 7. 端到端数据流图

用 ASCII 展示入口之间的数据依赖（上游的 Output 是下游的 Input）：

```
[Data_update]  ──Output──→  db_a.table_1, db_a.table_2
                                  │
                             Input ↓
[Optimizer]    ──Output──→  db_b.portfolio
                                  │
                             Input ↓
[Trading]      ──Output──→  db_c.trading_order
                                  │
                             Input ↓
[Tracking]     ──Output──→  db_c.tracking_result
```

---

## 护栏

- **只读操作**：绝不修改任何文件，绝不连接任何数据库
- **密码脱敏**：如需展示连接信息，密码必须脱敏
- **路径安全**：只扫描指定目录及其子目录，不越界
- **复用已有分析**：优先复用 `docs/` 下已有的分析报告，避免重复劳动
- **调用链深度**：最多追踪 3 层，避免过深迷失
- **标注不确定**：动态加载、反射调用、间接引用等无法静态追踪的，标注"待确认"
- **跳过副本**：跳过文件名含 `副本`、`_ori`、`_backup`、`_old` 的文件
- **大文件保护**：单文件超过 1000 行时，用 Grep 定位关键行再精读
