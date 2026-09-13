---
description: 对两张表做集合运算+值对比（交集、差集、逐列比值），输出深度对比报告
argument-hint: <host>:<port>:<user>:<password> A:<db>.<table> B:<db>.<table> key:<col1,col2> [--date YYYY-MM-DD] [--limit 50000]
disable-model-invocation: true
---

对一对表做深度对比：先跑集合运算（A∩B、A-B、B-A），再在交集内逐列比值。

理论基础见 `docs/table-compare-set-theory.md`。

## 前置条件

建议先运行 `/db-table-pair-check` 确认：
- 业务键已确定且唯一
- 键类型一致
- 值比较策略已明确

如果用户未运行预检，本命令在 Step 1 做快速验证，发现问题则中止并建议先跑预检。

## 参数

由用户提供，缺少时必须询问。**不从项目配置文件读取任何连接信息。**

- `$ARGUMENTS` 格式：`<host>:<port>:<user>:<password> A:<db>.<table> B:<db>.<table> [key:<col1,col2>] [--date YYYY-MM-DD] [--limit 50000]`
- `key:` 可选。不指定时自动在 `docs/` 下查找 `db-pair-check-{table}*.md` 预检报告，从中读取业务键和比较策略。如果预检报告也不存在，提示用户先运行 `/db-table-pair-check` 或手动指定 `key:`
- `--date` 可选，指定对比的日期或范围（如 `2026-03-30` 或 `2026-03-01~2026-03-30`），不指定则全量对比
- `--limit` 可选，值采样行数上限，默认 50000

**禁止在输出中粘贴密码。**

## 你的角色

你是一名**数据对比执行员**。你的任务是回答：**这两张表的数据，哪些一样、哪些不一样、差在哪？**

## 执行步骤

### Step 1: 快速验证

确认业务键在两表中都存在且类型一致：

```sql
SELECT TABLE_SCHEMA, COLUMN_NAME, COLUMN_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME IN ({key_cols})
  AND ((TABLE_SCHEMA='{db_a}' AND TABLE_NAME='{table_a}')
    OR (TABLE_SCHEMA='{db_b}' AND TABLE_NAME='{table_b}'))
ORDER BY COLUMN_NAME, TABLE_SCHEMA;
```

如果键列缺失或类型不兼容，中止并提示用户先运行 `/db-table-pair-check`。

### Step 2: 第一层 — 集合运算（记录存不存在）

#### 2a. 总量概览

```sql
SELECT COUNT(*) AS a_total FROM {A} [WHERE {date_filter}];
SELECT COUNT(*) AS b_total FROM {B} [WHERE {date_filter}];
```

#### 2b. 交集大小 |A ∩ B|

```sql
SELECT COUNT(*) AS intersection_cnt
FROM {A} a
JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
[WHERE {date_filter}];
```

#### 2c. A 独有 |A - B|

```sql
SELECT COUNT(*) AS a_only_cnt
FROM {A} a
LEFT JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
WHERE b.{key1} IS NULL
[AND {date_filter}];
```

#### 2d. B 独有 |B - A|

```sql
SELECT COUNT(*) AS b_only_cnt
FROM {B} b
LEFT JOIN {A} a ON b.{key1} = a.{key1} AND b.{key2} = a.{key2}
WHERE a.{key1} IS NULL
[AND {date_filter}];
```

#### 2e. 计算集合指标

```
|A| = a_total
|B| = b_total
|A ∩ B| = intersection_cnt
|A - B| = a_only_cnt
|B - A| = b_only_cnt
|A ∪ B| = |A| + |B| - |A ∩ B|

A→B 覆盖率 = |A ∩ B| / |A|
B→A 覆盖率 = |A ∩ B| / |B|
Jaccard    = |A ∩ B| / |A ∪ B|
```

验证恒等式：`|A| = |A ∩ B| + |A - B|`，`|B| = |A ∩ B| + |B - A|`。如果不成立，说明业务键有重复，中止并提示。

#### 2f. 差集样本

如果 |A - B| > 0，取样本帮助用户理解"A有B没有"的是什么数据：

```sql
SELECT a.{key1}, a.{key2}
FROM {A} a
LEFT JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
WHERE b.{key1} IS NULL
[AND {date_filter}]
LIMIT 20;
```

对 |B - A| 同理。

### Step 3: 第二层 — 交集内值对比（记录存在，值一不一致）

仅在 |A ∩ B| > 0 时执行。

#### 3a. 确定值列和比较方式

获取两表共同的非键列，排除审计列（ID, JSID, created_at, updated_at, InsertTime, UpdateTime）：

```sql
SELECT j.COLUMN_NAME, j.COLUMN_TYPE, j.IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS j
JOIN INFORMATION_SCHEMA.COLUMNS w ON j.COLUMN_NAME = w.COLUMN_NAME
WHERE j.TABLE_SCHEMA='{db_a}' AND j.TABLE_NAME='{table_a}'
  AND w.TABLE_SCHEMA='{db_b}' AND w.TABLE_NAME='{table_b}'
  AND j.COLUMN_NAME NOT IN ({key_cols}, 'ID','id','JSID','created_at','updated_at','InsertTime','UpdateTime','XGRQ')
ORDER BY j.ORDINAL_POSITION;
```

按数据类型确定比较方式：
- DECIMAL / INT / BIGINT / DATE / DATETIME / VARCHAR → `<=>` （NULL 安全精确比较）
- FLOAT / DOUBLE → `ABS(a.col - b.col) > 0.000001 OR NOT (a.col <=> b.col)`

#### 3b. 逐列不一致统计

对每个值列，统计交集中值不一致的行数：

```sql
SELECT
  '{col}' AS col_name,
  COUNT(*) AS compared,
  SUM(CASE WHEN NOT (a.{col} <=> b.{col}) THEN 1 ELSE 0 END) AS diff_cnt,
  ROUND(SUM(CASE WHEN NOT (a.{col} <=> b.{col}) THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS diff_pct
FROM {A} a
JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
[WHERE {date_filter}];
```

如果交集行数超过 `--limit`，改为采样：

```sql
... FROM (SELECT * FROM {A} [WHERE {date_filter}] LIMIT {limit}) a
JOIN {B} b ON ...
```

#### 3c. 不一致行的偏差分析（仅数值列）

对 diff_pct > 0 的数值列，计算偏差分布：

```sql
SELECT
  '{col}' AS col_name,
  COUNT(*) AS diff_rows,
  MIN(ABS(a.{col} - b.{col})) AS min_abs_diff,
  MAX(ABS(a.{col} - b.{col})) AS max_abs_diff,
  AVG(ABS(a.{col} - b.{col})) AS avg_abs_diff,
  MAX(CASE WHEN b.{col} != 0 THEN ABS(a.{col} - b.{col}) / ABS(b.{col}) END) AS max_rel_diff
FROM {A} a
JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
WHERE NOT (a.{col} <=> b.{col})
[AND {date_filter}];
```

#### 3d. 不一致样本

对每个不一致列，取几行样本展示具体差异：

```sql
SELECT a.{key1}, a.{key2}, a.{col} AS a_val, b.{col} AS b_val,
       ABS(a.{col} - b.{col}) AS abs_diff
FROM {A} a
JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
WHERE NOT (a.{col} <=> b.{col})
[AND {date_filter}]
ORDER BY ABS(a.{col} - b.{col}) DESC
LIMIT 10;
```

#### 3e. NULL 差异分析

对不一致行，区分差异类型：

```sql
SELECT
  '{col}' AS col_name,
  SUM(CASE WHEN a.{col} IS NULL AND b.{col} IS NOT NULL THEN 1 ELSE 0 END) AS a_null_b_not,
  SUM(CASE WHEN a.{col} IS NOT NULL AND b.{col} IS NULL THEN 1 ELSE 0 END) AS a_not_b_null,
  SUM(CASE WHEN a.{col} IS NOT NULL AND b.{col} IS NOT NULL AND a.{col} != b.{col} THEN 1 ELSE 0 END) AS both_not_null_diff
FROM {A} a
JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
WHERE NOT (a.{col} <=> b.{col})
[AND {date_filter}];
```

### Step 4: 综合评级

| 评级 | 条件 |
|------|------|
| ✅ 完全一致 | A=B（无差集，交集内所有列值一致） |
| ✅ 良好 | 覆盖率 >95%，交集一致率 >99% |
| ⚠️ 警告 | 覆盖率 80%-95%，或交集一致率 95%-99% |
| ❌ 严重差异 | 覆盖率 <80%，或交集一致率 <95% |

### Step 5: 输出报告

写入 `docs/db-pair-compare-{table_name}-{YYYYMMDD}.md`。

## 输出格式

```markdown
# 表对比报告：{table_a} vs {table_b}

> 对比时间: YYYY-MM-DD HH:MM
> A 表: {db_a}.{table_a}
> B 表: {db_b}.{table_b}
> 业务键: {key_cols}
> 日期范围: {date_range | 全量}
> 综合评级: ✅ / ⚠️ / ❌

---

## 一、第一层：集合运算（记录存不存在）

### 韦恩图

    ┌─────────────────────┐     ┌─────────────────────┐
    │         A           │     │         B           │
    │                 ┌───┼─────┼───┐                 │
    │   A - B         │  A ∩ B  │   │      B - A      │
    │   {a_only} 行   │{isect}行│   │   {b_only} 行   │
    │                 └───┼─────┼───┘                 │
    └─────────────────────┘     └─────────────────────┘

### 集合指标

| 指标 | 值 | 公式 |
|------|---|------|
| \|A\| | {a_total} | |
| \|B\| | {b_total} | |
| \|A ∩ B\| | {intersection} | |
| \|A - B\| | {a_only} | A有B没有 |
| \|B - A\| | {b_only} | B有A没有 |
| \|A ∪ B\| | {union} | \|A\| + \|B\| - \|A ∩ B\| |
| A→B 覆盖率 | {pct}% | \|A ∩ B\| / \|A\| |
| B→A 覆盖率 | {pct}% | \|A ∩ B\| / \|B\| |
| Jaccard 相似度 | {pct}% | \|A ∩ B\| / \|A ∪ B\| |

### 恒等式验证

- |A| = |A ∩ B| + |A - B| = {x} + {y} = {z} ✅/❌
- |B| = |A ∩ B| + |B - A| = {x} + {y} = {z} ✅/❌

### 差集样本

**A有B没有（前20条）：**

| {key1} | {key2} |
|--------|--------|

**B有A没有（前20条）：**

| {key1} | {key2} |
|--------|--------|

---

## 二、第二层：交集内值对比（值一不一致）

### 逐列一致性

| 列名 | 对比行数 | 不一致行数 | 不一致率 | 结论 |
|------|---------|-----------|---------|------|
| ClosePrice | {n} | {m} | {pct}% | ✅/⚠️/❌ |

### 不一致列偏差分析

#### {col_name}（不一致 {n} 行）

**偏差分布：**

| 最小绝对差 | 最大绝对差 | 平均绝对差 | 最大相对差 |
|-----------|-----------|-----------|-----------|

**差异类型：**

| A为NULL B有值 | A有值 B为NULL | 双方有值但不等 |
|-------------|-------------|--------------|

**最大偏差样本（前10条）：**

| {key1} | {key2} | A值 | B值 | 绝对差 |
|--------|--------|-----|-----|--------|

---

## 三、综合结论

| 维度 | 结论 | 详情 |
|------|------|------|
| 集合覆盖 | ✅/⚠️/❌ | ... |
| 值一致性 | ✅/⚠️/❌ | ... |
| 综合评级 | ✅/⚠️/❌ | ... |

### 建议
- ...
```

## 大表保护

- |A| 或 |B| 超过 **1000 万行** 且未指定 `--date` → 提示用户指定日期范围，或确认全量对比
- 交集超过 `--limit`（默认 5 万行）→ 值对比自动采样，标注"采样模式"
- 聚合查询（COUNT/MIN/MAX/AVG）不受限制
- 单条 SQL 超过 60 秒 → 跳过该步骤，标记"查询超时"

## 守护栏

- **只读操作** — 禁止任何写数据库操作
- **密码不输出** — 报告中不包含密码
- **不从项目配置文件读取连接信息** — 所有凭据由用户提供
- **恒等式验证** — 集合运算后必须验证 |A| = |A ∩ B| + |A - B|，不成立则中止
- **NULL 安全** — 值比较统一使用 `<=>` 运算符，不用 `=`
- **浮点容差** — FLOAT/DOUBLE 列用 `ABS() < ε`，DECIMAL 列用精确比较
- **不编造结论** — 超时或异常时如实标注
