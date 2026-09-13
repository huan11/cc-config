---
description: 对比两张表前的预检查（业务键发现、唯一性、类型一致性、值比较策略），确认集合模型是否成立
argument-hint: <host>:<port>:<user>:<password> A:<db>.<table> B:<db>.<table> [key:<col1,col2>]
disable-model-invocation: true
---

在对两张表做集合运算（交集、差集、值对比）之前，检查集合模型成立的前提条件。

理论基础见 `docs/table-compare-set-theory.md`。

## 参数

由用户提供，缺少时必须询问。**不从项目配置文件读取任何连接信息。**

- `$ARGUMENTS` 格式：`<host>:<port>:<user>:<password> A:<db>.<table> B:<db>.<table> [key:<col1,col2>]`
- 示例：`/db-table-pair-check myhost:3306:mh:Pass1 A:jydb.qt_dailyquote B:winddb.qt_dailyquote key:InnerCode,TradingDay`
- `key:` 为可选参数，不指定时由本命令自动发现
- 如果两表在不同实例，使用两组连接

**禁止在输出中粘贴密码。**

## 你的角色

你是一名**数据对比预检员**。你的任务是回答：**这两张表能不能做集合运算？如果能，用什么键、怎么比值？**

你不做实际的数据对比，只做前提条件检查。

## 执行步骤

### Step 1: 找业务键

如果用户指定了 `key:`，直接使用，跳到 Step 2。

如果未指定，按以下优先级自动发现：

**1a. 查主键**

```sql
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA='{db}' AND TABLE_NAME='{table}' AND CONSTRAINT_NAME='PRIMARY'
ORDER BY ORDINAL_POSITION;
```

如果主键是单列自增 ID（如 `ID bigint auto_increment`），则 ID 不适合做跨表配对键，继续往下找。

**1b. 查唯一索引 / 业务索引**

```sql
SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS cols
FROM INFORMATION_SCHEMA.STATISTICS
WHERE TABLE_SCHEMA='{db}' AND TABLE_NAME='{table}' AND INDEX_NAME != 'PRIMARY'
GROUP BY INDEX_NAME;
```

优先选取含日期列 + 实体编码列的组合索引（如 `InnerCode,TradingDay`）。

**1c. 启发式推断**

如果索引也找不到，按常见模式推断：

| 表类型 | 常见业务键 |
|--------|-----------|
| 日行情表 | 证券编码 + 日期（InnerCode+TradingDay, code+trade_date） |
| 证券主表 | 证券编码（InnerCode, SecuCode） |
| 财务数据 | 公司编码 + 报告期（CompanyCode+EndDate） |
| 成分股权重 | 指数编码 + 成分编码 + 日期 |

**1d. 两表列名不同时**

获取两表的列清单，尝试匹配语义相同的列：

```sql
SELECT COLUMN_NAME, DATA_TYPE, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA='{db}' AND TABLE_NAME='{table}'
ORDER BY ORDINAL_POSITION;
```

如果列名完全无法匹配（如 A 表用 `code`，B 表用 `InnerCode`），明确告知用户需要手动指定映射关系，或借助 `factor_code` 等映射表。

**1e. 完全找不到键**

如果以上都无法确定业务键，报告"无法找到配对键"，建议用户：
- 手动指定 `key:` 参数
- 或只做统计级对比（总行数、聚合值）

### Step 2: 检查唯一性

对两张表分别检查业务键是否唯一：

```sql
SELECT {key_cols}, COUNT(*) AS cnt
FROM {db}.{table}
GROUP BY {key_cols}
HAVING cnt > 1
LIMIT 10;
```

- 0 行 → ✅ 键唯一
- 有结果 → ❌ 有重复，报告重复数量和样本

如果是大表（>1000 万行），先用近似检查：

```sql
SELECT COUNT(*) AS total, COUNT(DISTINCT {key_cols}) AS distinct_cnt
FROM {db}.{table};
-- total = distinct_cnt → 唯一
```

### Step 3: 检查键的类型一致性

对比两表中业务键列的数据类型：

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (TABLE_SCHEMA='{db_a}' AND TABLE_NAME='{table_a}' AND COLUMN_NAME IN ({key_cols}))
   OR (TABLE_SCHEMA='{db_b}' AND TABLE_NAME='{table_b}' AND COLUMN_NAME IN ({key_cols}))
ORDER BY COLUMN_NAME, TABLE_SCHEMA;
```

检查项：

| 风险 | 示例 | 后果 |
|------|------|------|
| 字符 vs 数字 | VARCHAR '3455' vs INT 3455 | 隐式转换，索引失效，可能匹配错误 |
| 精度不同 | DECIMAL(10,2) vs DECIMAL(18,4) | 通常安全，但需注意 |
| 日期类型不同 | DATETIME vs DATE | 通常能匹配，但 DATETIME 的时间部分需为 00:00:00 |
| 编码不同 | utf8 vs utf8mb4 | 特殊字符可能不匹配 |

### Step 4: 确定值比较策略

获取两表的非键列（即需要比值的列），按数据类型分类：

```sql
SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA='{db}' AND TABLE_NAME='{table}'
  AND COLUMN_NAME NOT IN ({key_cols})
  AND COLUMN_NAME NOT IN ('ID','id','JSID','created_at','updated_at','InsertTime','UpdateTime')
ORDER BY ORDINAL_POSITION;
```

为每列确定比较方式：

| 数据类型 | 比较方式 | SQL |
|---------|---------|-----|
| INT / BIGINT | 精确相等 | `A.col = B.col` |
| DECIMAL | 精确相等 | `A.col = B.col` |
| FLOAT / DOUBLE | 容差比较 | `ABS(A.col - B.col) < ε` |
| VARCHAR / TEXT | 精确相等 | `A.col = B.col` |
| DATE / DATETIME | 精确相等 | `A.col = B.col` |

对所有 `IS_NULLABLE=YES` 的列，标记需要 NULL 安全比较（MySQL 用 `<=>`）。

### Step 5: 输出预检报告

同时输出到**对话**和**文件**。

写入 `docs/db-pair-check-{table_name}-{YYYYMMDD}.md`，供 `/db-table-pair-compare` 读取。

```markdown
# 表对比预检报告

> 预检时间: YYYY-MM-DD HH:MM
> A 表: {db_a}.{table_a}（{rows_a} 行，{cols_a} 列）
> B 表: {db_b}.{table_b}（{rows_b} 行，{cols_b} 列）
> 预检结论: ✅ 可以对比 / ❌ 不可对比 / ⚠️ 可以对比但需注意

## 1. 业务键

| 项目 | 结果 |
|------|------|
| 发现方式 | 主键 / 唯一索引 / 启发式 / 用户指定 |
| 键列 | {col1}, {col2} |
| A 表唯一性 | ✅ / ❌（N 条重复，样本：...） |
| B 表唯一性 | ✅ / ❌（N 条重复，样本：...） |
| 类型一致性 | ✅ / ⚠️（A: VARCHAR, B: INT → 隐式转换风险） |

## 2. 值比较策略

| 列名 | A 类型 | B 类型 | 可空 | 比较方式 |
|------|--------|--------|------|---------|
| ClosePrice | decimal(18,4) | decimal(18,4) | YES | `<=>` (NULL安全) |
| OpenPrice | float | decimal(18,4) | YES | `ABS() < ε` + NULL安全 |
| Volume | bigint | bigint | NO | `=` |

## 3. 推荐 JOIN 模板

```sql
SELECT ...
FROM {A} a JOIN {B} b ON a.{key1} = b.{key1} AND a.{key2} = b.{key2}
```
```

## 守护栏

- **只读操作** — 只执行 SELECT 和 INFORMATION_SCHEMA 查询，禁止任何写操作
- **密码不输出** — 报告中不包含密码
- **不做实际对比** — 只做预检，不执行交集/差集/值对比
- **不从项目配置文件读取连接信息** — 所有凭据由用户提供
- **大表保护** — 唯一性检查对大表（>1000万行）使用近似方式
- **不猜测业务键** — 无法确定时明确告知用户，不编造
