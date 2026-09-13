---
description: 验证重构后的 Data_update 代码写入数据库的结果是否与当前版本完全一致。
argument-hint: <baseline连接> <refactored连接> [target_date=YYYY-MM-DD]
---

以当前版本跑批结果（baseline）为基准，逐表逐行核对重构版本的写入结果，确认二者完全等价。

## 背景

Data_update 项目写入两个库共 22 张物理表（data_prepared_new + portfolio_new），每张表有固定的逻辑键（private_keys）。本命令依据 `docs/db-inventory-Data_update.md` 中定义的表结构和逻辑键，对 target_date 当日的写入数据做逐表精确对比。

## 输入

- `$ARGUMENTS` 格式：`<baseline_conn> <refactored_conn> [target_date]`
  - `baseline_conn`：当前版本写入的库，格式 `host:port:user:password`
  - `refactored_conn`：重构版本写入的库，格式 `host:port:user:password`
  - `target_date`：可选，默认今日，格式 `YYYY-MM-DD`
- 两库可以在同一台 MySQL 实例（库名不同），也可以在不同机器
- 参数不足时停下来询问，不猜测

## 你的角色

你是一名**重构验收员**。你的任务是回答：**重构后的代码，在 target_date 这一天写入的每一行数据，是否与当前版本完全一致？**

## 前置条件

两个库中，target_date 当日的数据都已写入完毕。如果某一侧尚未跑批，停下来告知用户。

## 表清单与检查规则

依据 `docs/db-inventory-Data_update.md`，按 `database_check.yaml` 中的分组模式逐表检查：

### data_prepared_new — delete+insert 表（按 valuation_date 当日对比）

| 表名 | 逻辑键 | 核心数值字段 |
|------|--------|------------|
| data_index | valuation_date, code | open, high, low, close, pct_chg, volume, amt |
| data_stock | valuation_date, code | open, high, low, close, pct_chg, vwap, volume, amt, adjfactor_jy, adjfactor_wind |
| data_stocknotrade | valuation_date, code | （无数值字段，只核对行存在性） |
| data_hkstock | valuation_date, code | open, high, low, close, pct_chg, vwap, volume, amt, adjfactor_jy, adjfactor_wind |
| data_future | valuation_date, code | close, settle, open, high, low, volume, amt, oi |
| data_option | valuation_date, code | close, settle, open, high, low, volume, amt, delta, impliedvol |
| data_etf | valuation_date, code | close, open, high, low, volume, amt, adjfactor |
| data_convertiblebond | valuation_date, code | close, conv_price, stock_price, std, delta |
| data_lhb | valuation_date | LHBProportion |
| data_factorexposure | valuation_date, code | size, beta, momentum, resvola, nlsize, btop, liquidity, earningsyield, growth（+ 31 个行业字段） |
| data_factorreturn | valuation_date | size, beta, momentum, resvola, nlsize, btop, liquidity, earningsyield, growth（+ 31 个行业字段） |
| data_factorpool | valuation_date, code | （无数值字段，只核对行存在性） |
| data_factorcov | valuation_date, factor_name | country, size, beta, momentum, resvola, nlsize, btop, liquidity, earningsyield, growth（+ 31 个行业字段） |
| data_factorspecificrisk | valuation_date, code | specificrisk |
| data_l4holding | valuation_date, product_code, code, mkt_value | quantity, price, unit_cost |
| data_l4info_processed | valuation_date, product_code | NetValue |
| data_score | valuation_date, code, score_name | final_score |

### data_prepared_new — append 表（只比对 target_date 当日新增行）

| 表名 | 逻辑键 | 核心数值字段 |
|------|--------|------------|
| data_vix | valuation_date, vix_type, organization | ch_vix |
| data_macro | valuation_date, type, name | value |
| data_us | valuation_date, type, name | value |
| data_internationalindex | valuation_date, code | open, high, low, close, pct_chg, volume |
| data_indexother | valuation_date, type, organization | value |
| data_factorindexexposure | valuation_date, organization | size, beta, momentum, resvola, nlsize, btop, liquidity, earningsyield, growth（+ 31 个行业字段） |
| data_l4info | valuation_date, product_code | NetAssetValue, GrossAssetValue, ProductNetValue, ProductReturn |
| st_stock | valuation_date, code | （只核对行存在性） |

### portfolio_new — 混合表

| 表名 | 写入模式 | 逻辑键 | 核心数值字段 |
|------|---------|--------|------------|
| portfolio | delete+insert | valuation_date, code, portfolio_name | weight |
| portfolio_info | append | valuation_date, score_name | mode_type, index_type, base_score |

### 静态表（跳过日常对比）

chinesevaluationdate、stockuniverse、specialday、index_info — 不参与本次对比（内容不随每日跑批变化）。

## 执行步骤

### Step 1: 解析参数，确认双侧数据就绪

分别查询两侧 target_date 当日已写入的表数量：

```sql
SELECT COUNT(DISTINCT TABLE_NAME) FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{db_name}';
```

同时对每张表取 `MAX(valuation_date)` 确认两侧当日均已写入，否则停下来告知用户哪一侧缺数据。

### Step 2: 逐表对比

对每张表，执行以下三项检查：

#### 2a. 行数对比

```sql
-- baseline 和 refactored 各执行
SELECT COUNT(*) AS row_count
FROM {db_name}.{table_name}
WHERE {date_column} = '{target_date}';
```

行数不等 → ❌ 立即标记，后续字段对比仍继续（以 baseline 为准）。

#### 2b. 仅 baseline 有、refactored 没有的行（缺失行）

```sql
-- 在 baseline 侧执行
SELECT {key_cols}
FROM baseline.{table_name}
WHERE valuation_date = '{target_date}'
  AND ({key_cols}) NOT IN (
    SELECT {key_cols} FROM refactored.{table_name}
    WHERE valuation_date = '{target_date}'
  )
LIMIT 10;
```

> 若两库在同一 MySQL 实例，直接跨库 JOIN；若不同机器，先将 baseline 当日数据导出为临时表再对比。

#### 2c. 数值字段差异（对逻辑键能匹配上的行）

对每张表的核心数值字段，按逻辑键 JOIN 后对比：

```sql
SELECT b.{key_cols},
       b.{num_col} AS baseline_val,
       r.{num_col} AS refactored_val,
       ABS(b.{num_col} - r.{num_col}) AS abs_diff
FROM baseline.{table_name} b
JOIN refactored.{table_name} r
  ON b.valuation_date = r.valuation_date
 AND b.{other_key_cols} = r.{other_key_cols}
WHERE b.valuation_date = '{target_date}'
  AND ABS(b.{num_col} - r.{num_col}) > 1e-6
LIMIT 10;
```

有差异行 → ❌ 列出前 10 条样例（字段名、baseline 值、refactored 值、差值）。

> 浮点容差：`ABS(diff) <= 1e-6` 视为相等，避免浮点精度误报。

### Step 3: 汇总

写入 `docs/verify-refactor-{YYYYMMDD}.md`。若当日已有报告，追加时间戳后缀。

## 输出格式

```markdown
# 重构验收报告 — Data_update

> 检查时间: YYYY-MM-DD HH:MM
> 目标日期: YYYY-MM-DD
> Baseline: {host}:{port}
> Refactored: {host}:{port}

---

## 总览

| 状态 | 表数 |
|------|------|
| ✅ 完全一致 | 18 |
| ❌ 存在差异 | 3 |
| ⏭️ 跳过（静态表） | 4 |

---

## 逐表结果

| # | 库 | 表名 | baseline 行数 | refactored 行数 | 行数差 | 缺失行 | 数值差异行 | 结论 |
|---|---|------|-------------|---------------|--------|--------|----------|------|
| 1 | data_prepared_new | data_stock | 5,432 | 5,432 | 0 | 0 | 0 | ✅ |
| 2 | data_prepared_new | data_score | 10,800 | 10,750 | -50 | 50 | — | ❌ |
| 3 | data_prepared_new | data_factorexposure | 5,000 | 5,000 | 0 | 0 | 12 | ❌ |

---

## 差异明细

### data_score — 缺失 50 行

> refactored 比 baseline 少 50 行，以下为 baseline 中存在但 refactored 中没有的 stock_code 样例：

| valuation_date | code | score_name |
|---------------|------|-----------|
| 2026-04-01 | 688001.SH | alpha_v3 |
| ... | | |

### data_factorexposure — 12 行数值差异

| valuation_date | code | 字段 | baseline | refactored | 差值 |
|---------------|------|------|---------|-----------|------|
| 2026-04-01 | 000001.SZ | size | 0.342819 | 0.342821 | 2e-6 |
| 2026-04-01 | 000002.SZ | momentum | -0.12345 | -0.12346 | 1e-5 |
```

## MySQL 连接方式

同库对比（同一 MySQL 实例，库名不同）：
```bash
mysql -h {host} -P {port} -u {user} -p'{password}' \
  -e "SELECT ... FROM baseline_db.table JOIN refactored_db.table ..."
```

跨机器对比（不同 MySQL 实例）：
1. 先将 baseline 当日数据导出为 CSV
2. 导入到 refactored 实例的临时表
3. 再执行 JOIN 对比
4. 对比完成后删除临时表

如本机无 mysql 客户端，改用 Python pymysql。

## 守护栏

- **只读操作** — 两侧库均只执行 SELECT，禁止任何写操作（临时表导入场景除外，完成后立即删除）
- **密码不输出** — 报告中不包含任何密码
- **浮点容差** — ABS(diff) ≤ 1e-6 视为相等，避免浮点精度误报
- **跳过静态表** — chinesevaluationdate、stockuniverse、specialday、index_info 不参与对比
- **不覆盖已有报告** — 若当日报告已存在，追加时间戳后缀
