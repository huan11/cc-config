---
description: 基于映射文档，对比两个数据库中已映射表的数据质量（以基准库为参照）
argument-hint: <host>:<port>:<user>:<password> baseline:<db> target:<db> [--mapping docs/db-table-mapping-*.md] [--tables t1,t2] [--date YYYY-MM-DD]
disable-model-invocation: true
---

使用 `/db-table-mapping` 生成的映射文档作为输入，逐对已映射表执行数据质量对比，以 baseline 库为基准，检查 target 库的数据完整性和一致性。

## 参数

由用户提供，缺少时必须询问。**不从项目配置文件读取任何连接信息。**

### 连接信息

- `$ARGUMENTS` 格式：`<host>:<port>:<user>:<password> baseline:<db> target:<db>`
- 同 `/db-table-mapping` 的连接格式

### 对比范围（可选）

- **--mapping**：映射文档路径。不指定则在 `docs/` 下查找最新的 `db-table-mapping-*.md`
- **--tables**：表名列表（逗号分隔）。不指定则对比映射文档中所有"确认映射"和"疑似映射（已确认 ☑）"的表对
- **--date**：对比的日期或日期范围（如 `2026-04-03` 或 `2026-04-01~2026-04-03`）。不指定则对比最近 3 个交易日

**禁止在输出中粘贴密码。**

## 你的角色

你是一名**数据质量审计员**。你的任务是回答：**对于每一对已映射的表，target 的数据质量与 baseline 相比如何？差在哪？**

## 前置条件

1. `docs/db-table-mapping-*.md` 必须存在。如果不存在，提示用户先运行 `/db-table-mapping`。
2. 如果映射文档中存在"疑似映射"且未被用户确认（仍为 ⬜），提醒用户先确认，或仅对比"确认映射"部分。

## 两种对比模式

### 模式 A: 同名表对比

两表列名相同，直接按列名对比。

### 模式 B: 异名表对比（列名映射）

两表列名不同，从映射文档的"列名对照"表中读取列映射关系。对比时按映射关系将 target 列对齐到 baseline 列名后再对比。

## 执行步骤

### Step 1: 加载映射文档，解析表对清单

从映射文档中提取：
- 所有确认映射的表对（同名 + 已确认的异名映射）
- 每对表的列名映射关系（同名表为 1:1，异名表从文档读取）
- 排除未确认的疑似映射（⬜ 标记）

如果用户指定了 `--tables`，只保留指定的表对。

### Step 2: 日期列检测

按以下优先级确定每张表的日期列：

1. 常见日期列名：`TradingDay`, `EndDate`, `valuation_date`, `trade_date`, `InfoPublDate`
2. `INFORMATION_SCHEMA.COLUMNS` 中类型为 `date` / `datetime` 的列
   - 唯一则自动选用；多个则按列名优先级选择
3. 以上都没有 → 标记为"无日期列"，整表一次性对比

异名表注意：baseline 和 target 的日期列名可能不同（如 TradingDay vs trade_date），从映射文档读取对应关系。

### Step 3: 主键/对比键检测

优先级：
1. 映射文档中标注的对比键
2. `INFORMATION_SCHEMA.KEY_COLUMN_USAGE` 中的 PRIMARY KEY
3. 常见组合键：(日期列, SecuCode/code/InnerCode)
4. 以上都没有 → 仅对比聚合统计，跳过行级对比

异名表注意：两侧主键列名可能不同，使用列名映射对齐。

### Step 4: 逐表对比（6 个维度）

对每对已映射表执行以下检查：

#### 4a. 列结构对比

- Baseline 有但 Target 没有的列（按映射关系对齐后）
- Target 额外列（Baseline 中无对应）
- 同映射列的数据类型是否兼容

#### 4b. 行数对比

```sql
-- 按日期取 COUNT
SELECT COUNT(*) FROM {db}.{table}
WHERE {date_col} BETWEEN '{start_date}' AND '{end_date}';
```

两侧按日期逐日对比 COUNT(*)，计算差值和差异比。

#### 4c. 日期覆盖范围

```sql
SELECT MIN({date_col}) AS earliest, MAX({date_col}) AS latest,
       COUNT(DISTINCT {date_col}) AS date_count
FROM {db}.{table};
```

对比两侧的时间跨度和日期密度。标记 target 缺失的日期范围。

#### 4d. NULL 率对比

对每个映射列，在指定日期范围内：

```sql
SELECT '{col}' AS col_name,
       COUNT(*) AS total,
       SUM(CASE WHEN {col} IS NULL THEN 1 ELSE 0 END) AS null_count,
       ROUND(SUM(CASE WHEN {col} IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS null_pct
FROM {db}.{table}
WHERE {date_col} BETWEEN '{start_date}' AND '{end_date}';
```

两侧 NULL 率差异超过 5% → 标记 ⚠️。

#### 4e. 数值范围抽样

对数值列（decimal/int/float/double）：

```sql
SELECT '{col}' AS col_name,
       MIN({col}), MAX({col}), AVG({col}), STDDEV({col}),
       COUNT(DISTINCT {col}) AS distinct_count
FROM {db}.{table}
WHERE {date_col} = '{date}' AND {col} IS NOT NULL;
```

对比两侧 MIN/MAX/AVG/STDDEV 差异，标记分布偏移。

#### 4f. 值采样对比（需要对比键）

按对比键 JOIN 两侧数据，对数值列计算：
- 匹配记录数 vs 不匹配记录数
- 最大绝对差
- 最大相对差
- 不一致行占比

浮点容差：ABS(diff) <= 1e-6 视为相等。

**同实例优化（两库在同一 host:port）：**
```sql
SELECT b.{key}, b.{col} AS baseline_val, t.{col} AS target_val,
       ABS(b.{col} - t.{col}) AS abs_diff
FROM {baseline_db}.{baseline_table} b
JOIN {target_db}.{target_table} t ON b.{key} = t.{key}
WHERE b.{date_col} = '{date}'
  AND ABS(b.{col} - t.{col}) > 1e-6
LIMIT 100;
```

### Step 5: 逐表评级

根据 6 个维度的结果，给出综合评级：

- **✅ 良好**：结构一致、行数接近（±5%）、时间覆盖一致、无显著空值/数值差异
- **⚠️ 警告**：存在小幅偏差（行数差 5%-20%、少量字段差异、个别空值差异）
- **❌ 异常**：结构差异大、行数差异 >20%、时间覆盖断裂、大量空值或数值偏差

### Step 6: 输出报告

写入 `docs/db-quality-compare-{baseline_db}-vs-{target_db}-{YYYYMMDD}.md`。

## 输出格式

```markdown
# 数据质量对比报告

> 对比时间: YYYY-MM-DD HH:MM
> Baseline: {host}:{port} / {baseline_db}
> Target: {host}:{port} / {target_db}
> 映射文档: docs/db-table-mapping-*.md
> 对比日期: YYYY-MM-DD（或范围）
> 对比表对: N 对（同名 X 对 + 异名 Y 对）

---

## 一、总览

| 状态 | 表对数 |
|------|--------|
| ✅ 质量一致 | X |
| ⚠️ 存在差异 | Y |
| ❌ 严重差异 | Z |
| ⏭️ 跳过 | W |

---

## 二、逐表总结

| # | Baseline 表 | Target 表 | 映射类型 | 列结构 | 行数 | 日期覆盖 | NULL率 | 数值分布 | 值采样 | 综合 |
|---|------------|----------|---------|--------|------|---------|--------|---------|--------|------|

---

## 三、逐表详情

### {N}. {baseline_table} ↔ {target_table}（{映射类型}）

#### 列结构

| 检查项 | 结论 | 详情 |
|--------|------|------|

#### 行数对比

| 日期 | Baseline | Target | 差值 | 差异% | 结论 |
|------|---------|--------|------|-------|------|

#### 日期覆盖

| 侧 | 最早日期 | 最晚日期 | 日期数 |
|----|---------|---------|--------|

#### NULL 率对比

| 列名 | Baseline NULL% | Target NULL% | 差异 | 结论 |
|------|---------------|-------------|------|------|

#### 数值范围

| 列名 | 侧 | MIN | MAX | AVG | STDDEV |
|------|-----|-----|-----|-----|--------|

#### 值采样

| 列名 | 对比行数 | 最大绝对差 | 最大相对差 | 不一致行 | 结论 |
|------|---------|-----------|-----------|---------|------|

---

## 四、汇总建议

| 差异类别 | 涉及表对 | 严重度 | 建议 |
|---------|---------|--------|------|
```

## 大表保护

- 单表过滤后超过 **5 万行** → 值采样对比自动启用 `LIMIT 50000`
- 超过 **50 万行** → 跳过值采样（Step 4f），仅对比聚合统计，标注"大表，跳过行级对比"
- 聚合查询（COUNT/MIN/MAX/AVG）不受行数限制
- 执行前向用户确认表对数量，超过 30 对时分批执行

## 守护栏

- **只读操作** — 只执行 SELECT 和 INFORMATION_SCHEMA 查询，禁止任何写操作
- **密码不输出** — 报告中不包含密码
- **依赖映射文档** — 不自行发现映射关系，严格以映射文档为准
- **不覆盖已有报告** — 若当日报告已存在，追加时间戳后缀（如 `-v2`）
- **只写报告文件** — 输出到 `docs/db-quality-compare-*.md`，不修改任何已有文件
- **不从项目配置文件读取连接信息** — 所有凭据由用户提供
- **超时控制** — 单条 SQL 30 秒超时，单表所有维度 3 分钟超时；超时则跳过标记
- **大表保护** — 超过 5 万行自动限制采样范围，超过 50 万行跳过行级对比
- **不编造对比结论** — 超时或异常时如实标注，不猜测数据
- **浮点容差** — 数值对比允许 1e-6 误差
