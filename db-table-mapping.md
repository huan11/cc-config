---
description: 发现并记录两个数据库之间的语义表映射关系（表级对应关系）
argument-hint: <host>:<port>:<user>:<password> baseline:<db> target:<db>
disable-model-invocation: true
---

以 baseline 库为基准，发现 target 库中哪些表与 baseline 的表存在语义对应关系，输出一份分类映射文档，供后续 `/db-quality-compare` 使用。

## 参数

由用户提供，缺少时必须询问。**不从项目配置文件读取任何连接信息。**

- `$ARGUMENTS` 格式：`<host>:<port>:<user>:<password> baseline:<db> target:<db>`
- 示例：`/db-table-mapping myhost.rds.aliyuncs.com:3306:mh:Pass1 baseline:jydb target:winddb`
- 如果密码含冒号，用引号包裹整段连接串
- 如果两库不在同一实例，使用两组连接：`baseline:<host>:<port>:<user>:<password>:<db> target:<host>:<port>:<user>:<password>:<db>`

**禁止在输出中粘贴密码。**

## 你的角色

你是一名**数据库资产测绘员**。你的任务是回答：**target 库的每张表，在 baseline 库中有没有语义对应的表？对应关系是什么？**

你不做数据质量对比，只建立表级映射。

## 执行步骤

### Step 1: 获取双侧表清单

分别查询两个库的全部表名、表注释、行数估算：

```sql
SELECT TABLE_NAME, TABLE_COMMENT, TABLE_ROWS, DATA_LENGTH
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{db_name}' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
```

输出双侧表数量汇总，向用户确认范围。

### Step 2: 精确名称匹配（Signal 1 — 同名表）

对比两侧表名（不区分大小写），找出同名表，直接归为"确认映射"。

### Step 3: 查询映射表（Signal 2 — 已有映射元数据）

检查 target 库是否存在映射/字典表：

```sql
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{target_db}'
  AND (TABLE_NAME LIKE '%map%' OR TABLE_NAME LIKE '%code%'
       OR TABLE_NAME LIKE '%dict%' OR TABLE_NAME LIKE '%config%');
```

如果找到 `factor_code` 或类似表，读取全部内容：

```sql
SELECT * FROM {target_db}.factor_code;
```

从中提取：
- `InfoTable` / `QuoteTable` 等列中出现的表名 → 这些表存在跨库关联
- `ColumnName` / `ColumnName2` → 列级映射线索
- 构建表级对应关系的额外证据

### Step 4: 列结构相似度分析（Signal 3 — 异名表候选）

对 Step 2 中**未匹配的表**，一次性获取双侧全部列信息：

```sql
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '{db_name}'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

计算每对跨库非同名表的列名重合度：
- 排除通用列（id, ID, JSID, created_at, updated_at, InsertTime, UpdateTime）后计算
- Jaccard 相似度 = |共同列名| / |并集列名|
- 阈值：> 0.5 为"高相似"，0.3~0.5 为"中相似"，< 0.3 忽略
- 对每个 target 未匹配表，找出 baseline 中相似度最高的表

### Step 5: 列注释语义分析（Signal 4 — 辅助确认）

对 Step 4 中相似度 > 0.3 的候选对，进一步分析：
- 共同列的 COLUMN_COMMENT 是否语义一致（中文注释关键词匹配）
- TABLE_COMMENT 是否描述同一业务域
- 将语义匹配结果与结构相似度综合评分，给出置信度（高/中/低）

### Step 6: 分类 target 独有表

对 target 中无映射候选的表，按命名模式自动分类：

**6a. _dev 后缀 → 开发/测试副本**
```sql
-- 找出正式表名
SELECT REPLACE(TABLE_NAME, '_dev', '') AS base_name
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{target_db}' AND TABLE_NAME LIKE '%\_dev';
```

**6b. 简化行情表（trade_date + code + close 模式）→ 派生聚合表**
```sql
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '{target_db}' AND COLUMN_NAME = 'trade_date'
INTERSECT
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '{target_db}' AND COLUMN_NAME = 'code'
INTERSECT
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '{target_db}' AND COLUMN_NAME = 'close';
```

对这类表，尝试推断可能的 baseline 来源表（基于业务域关键词：stock→qt_dailyquote, index→qt_indexquote, future→fut_tradingquote 等）。

**6c. 宏观指标表** — 表名为常见宏观经济指标（cpi, pmi, ppi, m1m2, shibor 等），通常无 baseline 对应。

**6d. 其他** — 以上均不匹配的表，标记为"待人工确认"。

### Step 7: 输出映射文档

写入 `docs/db-table-mapping-{baseline_db}-vs-{target_db}-{YYYYMMDD}.md`。

## 输出格式

```markdown
# 数据库表映射文档

> 生成时间: YYYY-MM-DD HH:MM
> Baseline: {host}:{port} / {baseline_db} (N 张表)
> Target: {host}:{port} / {target_db} (M 张表)

---

## 一、映射总览

| 类别 | 数量 | 说明 |
|------|------|------|
| 确认映射（同名） | X | 两库表名完全一致 |
| 疑似映射（异名同构） | Y | 不同表名但结构/语义高度相似 |
| Target 独有 — 派生聚合表 | A | 简化行情结构，可能从 baseline 风格表聚合而来 |
| Target 独有 — 宏观指标表 | B | 无 baseline 对应 |
| Target 独有 — 开发副本 | C | _dev 后缀 |
| Target 独有 — 其他 | D | 待人工确认 |
| Baseline 独有 | E | Target 中无对应 |

---

## 二、确认映射（同名表）

| # | 表名 | Baseline 行数 | Target 行数 | Baseline 列数 | Target 列数 | 备注 |
|---|------|-------------|-----------|-------------|-----------|------|

---

## 三、疑似映射（异名同构）

| # | Target 表名 | 候选 Baseline 表名 | 列名重合度 | 映射依据 | 置信度 |
|---|------------|-------------------|-----------|---------|--------|

### 逐对详情

#### {target_table} ↔ {baseline_table}（置信度: X）

**映射依据:**
1. [列出所有匹配信号：factor_code 引用、列名重合度、注释语义等]

**列名对照:**

| Target 列 | 候选 Baseline 列 | 匹配方式 |
|-----------|-----------------|---------|

**用户确认:** ⬜ 请确认此映射是否正确

---

## 四、Target 独有表

### 4a. 派生聚合表

| # | 表名 | 行数 | 列数 | 特征 | 可能的 Baseline 来源 |
|---|------|------|------|------|-------------------|

### 4b. 宏观指标表

| # | 表名 | 行数 | 列数 | TABLE_COMMENT |
|---|------|------|------|---------------|

### 4c. 开发/测试副本（_dev 后缀）

| # | 表名 | 对应正式表 | 行数差异 |
|---|------|-----------|---------|

### 4d. 待人工确认

| # | 表名 | 行数 | 列清单 | 无映射原因 |
|---|------|------|--------|-----------|

---

## 五、Baseline 独有表

| # | 表名 | 行数 | TABLE_COMMENT | 说明 |
|---|------|------|---------------|------|

---

## 六、映射元数据（factor_code 表内容）

| wind_code | jydb_code | InfoTable | QuoteTable | ColumnName | ColumnName2 |
|-----------|-----------|-----------|------------|------------|-------------|
```

## 守护栏

- **只读操作** — 只执行 SELECT 和 INFORMATION_SCHEMA 查询，禁止任何写操作
- **密码不输出** — 报告中不包含密码
- **只写映射文档** — 输出到 `docs/db-table-mapping-*.md`，不修改任何已有文件
- **不猜测映射** — 疑似映射必须标注置信度和依据，不编造对应关系
- **保留用户确认位** — 疑似映射留有 ⬜ 确认框，不自动标记为已确认
- **Jaccard 计算排除通用列** — id, ID, JSID, created_at, updated_at, InsertTime, UpdateTime 等不参与相似度计算
- **不从项目配置文件读取连接信息** — 所有凭据由用户提供
- **超时处理** — 单条 SQL 超过 30 秒则跳过，标记"查询超时"；`INFORMATION_SCHEMA.TABLES` 超时则改用 `SHOW TABLE STATUS FROM {db}`
