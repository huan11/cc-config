---
description: 连接数据库，将 db-inventory 文档与实际数据库进行核对，输出差异报告。
argument-hint: <host>:<port>:<user>:<password>
---

读取 `docs/db-inventory-*.md` 中记录的表清单，连接实际数据库，逐项核对并输出差异报告。

## 输入

- `$ARGUMENTS`：`<host>:<port>:<user>:<password>`，冒号分隔。
- **不从项目配置文件读取任何连接信息**，因为配置文件中可能是生产环境凭据。
- 如果参数不足 4 段（冒号分隔），停下来询问用户补全，不要猜测或从配置文件填充。
- 如果密码中包含冒号，用户应将密码用引号包裹或改用空格分隔格式 `<host> <port> <user> <password>`。

## 你的角色

你是一名**数据库审计员**。你的任务是回答：**文档里说的和数据库里实际的，哪里对不上？**

## 前置条件

`docs/db-inventory-*.md` 必须存在。如果不存在，提示用户先运行 `/extract-db-inventory-from-repo-outputs`。

如果匹配到**多个** db-inventory 文件，列出所有匹配项让用户选择，不要自动合并。

## 执行步骤

### Step 1: 解析参数 & 加载文档基线

从用户参数中解析连接四要素（冒号分隔）：host、port、user、password。

从 db-inventory 中**只提取文档基线**：
- 所有数据库名（如 `data_prepared_new`、`portfolio_new`）
- 每张表的：表名、表注释、字段列表、字段类型、逻辑键

> 注意：db-inventory 中存储的是"逻辑键"（YAML `private_keys`，应用层 delete 条件），不一定是数据库 PRIMARY KEY。

### Step 2: 连接数据库并核对

对每个数据库，通过 Bash 执行 `mysql` 命令查询。**所有 SQL 都通过命令行执行，不写临时脚本文件。**

核对 4 个维度：

#### 2a. 表存在性

```sql
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{db_name}';
```

对比文档：
- 文档有、库里没有 → **缺失表**
- 库里有、文档没有 → **未登记表**

#### 2b. 字段匹配

对文档中的每张表：

```sql
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '{db_name}' AND TABLE_NAME = '{table_name}'
ORDER BY ORDINAL_POSITION;
```

对比文档：
- 文档有、表里没有的字段 → **缺失字段**
- 表里有、文档没有的字段 → **未登记字段**
- 类型不匹配（如文档说 Float 实际是 varchar） → **类型不一致**

#### 2c. 数据新鲜度

按以下优先级确定日期列：
1. `valuation_date`（项目约定的标准日期字段）
2. db-inventory 逻辑键中类型为日期的字段
3. `information_schema.COLUMNS` 中类型为 `date` 的列（若唯一则自动选用，多个则标注"多日期列，跳过"）
4. 以上都没有 → 标记为"无日期字段"

对有日期列的表：

```sql
SELECT MAX({date_column}) AS latest_date, COUNT(*) AS total_rows
FROM {table_name};
```

标记：
- 最新日期距今超过 3 个交易日 → **数据滞后**
- 总行数为 0 → **空表**

#### 2d. 数据量级概览

```sql
SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH, UPDATE_TIME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{db_name}';
```

### Step 3: 输出报告

写入 `docs/db-check-report-{YYYYMMDD}.md`。

## 输出格式

```markdown
# 数据库核对报告

> 核对时间: YYYY-MM-DD HH:MM
> 基线文档: docs/db-inventory-*.md
> 目标主机: {host}:{port}
> 核对数据库: db1, db2

---

## 一、核对总览

| 维度 | 通过 | 异常 | 详情 |
|------|------|------|------|
| 表存在性 | 30/32 | 2 | 见 §二 |
| 字段匹配 | 28/32 | 4 | 见 §三 |
| 数据新鲜度 | 25/32 | 7 | 见 §四 |

---

## 二、表存在性

### 文档有、库里没有（缺失表）

| # | 文档表名 | 所属库 | 文档中的表注释 |
|---|---------|--------|--------------|

### 库里有、文档没有（未登记表）

| # | 实际表名 | 所属库 | 行数 |
|---|---------|--------|------|

---

## 三、字段差异

<!-- 只列有差异的表，完全匹配的表不列出 -->

### data_xxx

| 差异类型 | 字段名 | 文档定义 | 实际定义 |
|---------|--------|---------|---------|
| 缺失字段 | col_a | String(50) | (不存在) |
| 未登记字段 | col_b | (未登记) | varchar(100) |
| 类型不一致 | col_c | Float | varchar(50) |

---

## 四、数据新鲜度

| # | 表名 | 表注释 | 最新日期 | 距今天数 | 总行数 | 状态 |
|---|------|--------|---------|---------|--------|------|
| 1 | data_index | 指数日行情 | 2026-03-28 | 1 | 12,345 | OK |
| 2 | data_macro | 宏观指标 | 2026-03-25 | 4 | 8,900 | ⚠️ 滞后 |
| 3 | stockUniverse | 股票列表 | — | — | 5,000 | (无日期字段) |

---

## 五、数据量级

| # | 库 | 表名 | 估算行数 | 数据大小 | 最后更新时间 |
|---|---|------|---------|---------|------------|
```

## MySQL 连接方式

优先使用命令行 mysql 客户端：

```bash
mysql -h {host} -P {port} -u {user} -p'{password}' -e "SQL" {db_name}
```

如果本机没有 mysql 客户端，尝试通过 Python 执行：

```bash
python3 -c "
import pymysql
conn = pymysql.connect(host='{host}', port={port}, user='{user}', password='{password}', database='{db_name}')
cursor = conn.cursor()
cursor.execute('SQL')
for row in cursor.fetchall():
    print(row)
conn.close()
"
```

## 守护栏

- **只读操作** — 只执行 SELECT 和 INFORMATION_SCHEMA 查询，禁止任何写操作
- **密码不输出** — 报告中不包含密码，Bash 命令的密码参数不会被记录
- **不修改已有文件** — 只写 `docs/db-check-report-{YYYYMMDD}.md`
- **超时控制** — 单条 SQL 超过 30 秒则跳过，标记为"查询超时"
- **字段对比容忍度** — MySQL 的 `float` / `double` 都算匹配文档的 `Float`；`varchar` 匹配 `String`
