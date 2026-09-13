---
description: 核对单次跑批写入结果，以生产环境为基准验证数据一致性。
argument-hint: <测试库连接> <生产库连接> [target_date=YYYY-MM-DD]
---

对单次跑批的数据库写入结果做质检：先检查更新状态（表是否写入），再以生产环境同日数据为基准做一致性对比，输出差异报告。

## 输入

- `$ARGUMENTS` 格式：`<host>:<port>:<user>:<password> <prod_host>:<prod_port>:<prod_user>:<prod_password> [target_date]`
  - 第一组：**待检环境**（本次跑批写入的库）
  - 第二组：**生产环境**（基准，只读）
  - `target_date` 可选，默认今日，格式 `YYYY-MM-DD`
- 两组连接参数用空格分隔，组内用冒号分隔
- 参数不足时停下来询问，不猜测

## 你的角色

你是一名**跑批质检员**。你的任务是回答两个问题：
1. **写进去了吗？**（更新状态）
2. **和生产环境对得上吗？**（数据一致性）

## 前置条件

`docs/db-inventory-*.md` 必须存在。如果不存在，提示用户先运行 `/extract-db-inventory-from-repo-outputs`。

## 执行步骤

### Step 1: 解析参数

解析两组连接四要素和 target_date。

从 db-inventory 中加载每张表的：
- 表名、所属库
- 日期字段（优先 `valuation_date`，其次逻辑键中类型为日期的字段）
- 写入模式（delete+insert / append / 静态）
- 逻辑键（`private_keys`）

### Step 2: 采集当前状态（待检环境）

对每张有日期字段的表：

```sql
SELECT MAX({date_column}) AS latest_date,
       COUNT(*) AS total_rows
FROM {db_name}.{table_name};
```

对无日期字段的静态表只取 COUNT(*)。

### Step 3: 更新状态判定

| 写入模式 | 通过条件 |
|---------|---------|
| delete+insert | `latest_date == target_date` |
| append | `latest_date == target_date` |
| 静态表 | 行数 > 0 |

异常：
- `latest_date < target_date` → ⚠️ 未更新
- `latest_date > target_date` → ℹ️ 预生成（T+1，正常）
- `total_rows == 0` → ❌ 空表

> 未更新的表跳过后续一致性检查，直接标记异常。

### Step 4: 数据一致性检查（对比生产）

**仅对 `latest_date == target_date` 的表执行。**

对每张表，分别在待检环境和生产环境查询 target_date 当日数据，逐项对比：

#### 4a. 行数对比

```sql
-- 待检 & 生产各执行
SELECT COUNT(*) AS row_count
FROM {db_name}.{table_name}
WHERE {date_column} = '{target_date}';
```

- 差值 = 0 → ✅
- 差值 ≠ 0 → ❌ 行数不一致（列出差值和百分比）

#### 4b. 重复行检测（仅待检环境）

按逻辑键检测：

```sql
SELECT {key_cols}, COUNT(*) AS cnt
FROM {db_name}.{table_name}
WHERE {date_column} = '{target_date}'
GROUP BY {key_cols}
HAVING cnt > 1
LIMIT 5;
```

有结果 → ❌ 存在重复行

#### 4c. 关键字段空值率对比

对 db-inventory 中定义的核心数值字段（每表取最关键的 2~3 个），分别查询待检和生产的空值率：

```sql
SELECT
  ROUND(SUM(CASE WHEN {col} IS NULL THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS null_pct
FROM {db_name}.{table_name}
WHERE {date_column} = '{target_date}';
```

- 待检空值率 > 生产空值率 + 5% → ⚠️ 空值率偏高
- 待检空值率 > 生产空值率 + 20% → ❌ 严重

#### 4d. 数值分布对比

对核心数值字段，比较 AVG 和 STDDEV：

```sql
SELECT AVG({col}) AS avg_val, STDDEV({col}) AS std_val
FROM {db_name}.{table_name}
WHERE {date_column} = '{target_date}';
```

- AVG 偏差 > 10% → ⚠️ 均值偏差较大
- STDDEV 偏差 > 30% → ⚠️ 分布差异较大

> 数值字段范围检查依赖生产均值，而非硬编码阈值。

#### 4e. 跨表行数一致性（待检环境内）

| 检查对 | 预期关系 |
|--------|---------|
| `data_factorpool` vs `data_factorexposure` | 行数相等（同一股票池） |
| `data_factorpool` vs `data_factorspecificrisk` | 行数相等 |
| `data_stocknotrade` ⊂ `data_stock` | stocknotrade 的 stock_code 全部存在于 data_stock |

### Step 5: 输出报告

写入 `docs/verify-run-{YYYYMMDD}.md`。若当日已有报告，追加时间戳后缀（如 `verify-run-20260401-1430.md`）。

## 输出格式

```markdown
# 跑批质检报告

> 检查时间: YYYY-MM-DD HH:MM
> 目标日期: YYYY-MM-DD
> 待检环境: {host}:{port}
> 生产环境: {prod_host}:{prod_port}

---

## 总览

| 维度 | 通过 | 异常 | 严重 |
|------|------|------|------|
| 更新状态 | 20/22 | 2 | 0 |
| 行数对比（vs 生产） | 19/20 | 1 | 0 |
| 重复行 | 20/20 | 0 | 0 |
| 空值率对比（vs 生产） | 19/20 | 1 | 0 |
| 数值分布对比（vs 生产） | 18/20 | 2 | 0 |
| 跨表一致性 | 3/3 | 0 | 0 |

---

## 一、更新状态

| # | 库 | 表名 | 写入模式 | 最新日期 | 当日行数 | 状态 |
|---|---|------|---------|---------|--------|------|
| 1 | data_prepared_new | data_stock | delete+insert | 2026-04-01 | 5,432 | ✅ OK |
| 2 | data_prepared_new | data_macro | delete+insert | 2025-12-19 | — | ⚠️ 未更新，跳过一致性检查 |

---

## 二、数据一致性（对比生产）

### 行数对比

| 表名 | 待检行数 | 生产行数 | 差值 | 状态 |
|------|---------|---------|------|------|
| data_stock | 5,432 | 5,430 | +2 | ✅ |
| data_score | 10,700 | 10,800 | -100 | ⚠️ 差 100 行（-0.9%） |

### 重复行

| 表名 | 逻辑键 | 重复组数 | 状态 |
|------|--------|---------|------|
| data_factorexposure | (valuation_date, stock_code) | 0 | ✅ |

### 空值率对比

| 表名 | 字段 | 待检空值率 | 生产空值率 | 差值 | 状态 |
|------|------|----------|----------|------|------|
| data_stock | close | 0% | 0% | 0% | ✅ |
| data_hkstock | volume | 7.2% | 1.1% | +6.1% | ⚠️ |

### 数值分布对比

| 表名 | 字段 | 待检 AVG | 生产 AVG | 偏差 | 待检 STDDEV | 生产 STDDEV | 状态 |
|------|------|---------|---------|------|-----------|-----------|------|
| data_stock | close | 18.32 | 18.28 | 0.2% | 24.1 | 23.9 | ✅ |
| data_score | score | 0.021 | 0.019 | 10.5% | 0.31 | 0.28 | ⚠️ 均值偏差 |

### 跨表一致性

| 检查对 | 预期 | 差值 | 状态 |
|--------|------|------|------|
| data_factorpool vs data_factorexposure | 行数相等 | 0 | ✅ |
| data_factorpool vs data_factorspecificrisk | 行数相等 | 0 | ✅ |

---

## 三、异常汇总

| 优先级 | 类别 | 表名 | 问题描述 |
|--------|------|------|---------|
| ⚠️ | 未更新 | data_macro | 最新日期 2025-12-19，滞后 103 天 |
| ⚠️ | 行数差异 | data_score | 比生产少 100 行（-0.9%） |
| ⚠️ | 空值率偏高 | data_hkstock | volume 空值率 7.2%（生产 1.1%） |
| ⚠️ | 均值偏差 | data_score | score 均值偏差 10.5% |
```

## MySQL 连接方式

```bash
mysql -h {host} -P {port} -u {user} -p'{password}' -e "SQL" {db_name}
```

如果本机没有 mysql 客户端，改用 Python pymysql 执行。

## 守护栏

- **只读操作** — 只执行 SELECT 查询，禁止任何写操作
- **密码不输出** — 报告中不包含任何密码
- **生产环境只读** — 生产环境连接仅用于 SELECT，严禁写操作
- **不覆盖已有报告** — 若当日报告已存在，追加时间戳后缀
- **超时控制** — 单条 SQL 超过 30 秒则跳过，标记为"查询超时"
- **未更新表跳过** — Step 3 判定为未更新的表，不进入 Step 4，避免对空数据做无效对比
