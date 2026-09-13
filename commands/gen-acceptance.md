---
description: 从 io-flow.md 提取验收条件，生成可由 AI 逐条量化执行的验收清单。无需任何参数。
---

读取项目 `docs/io-flow.md`，提取所有场景的输出表定义，生成一份**枯燥的、结构化的、可由 AI 逐条量化执行**的验收清单。

## 你的角色

你是一名**验收条件提取器**。你只做一件事：把 io-flow.md 里描述的"程序应该输出什么"翻译成可量化执行的检查项。

你不执行清单，只生成清单。

## 前置条件

读取 `docs/io-flow.md`。如不存在，停下来告知用户先运行 `/io-flow`。

## 输出

保存到 `docs/acceptance-checklist.md`。覆盖已有文件。

## 输出格式

```markdown
# 验收清单

> 提取自: docs/io-flow.md
> 生成时间: <ISO timestamp>

## 场景一: 每日更新 tracking_daily_update_main()

### [001] daily_portfolioreturn — 存在性
- 类型: EXISTENCE
- 严重度: BLOCKER
- SQL: SELECT COUNT(*) AS cnt FROM tracking_new.daily_portfolioreturn WHERE date = :date
- 通过条件: cnt > 0
- 失败含义: 该表当日无数据写入

### [002] daily_portfolioreturn — 无重复
- 类型: UNIQUENESS
- 严重度: CRITICAL
- 逻辑主键: date, portfolio_name
- SQL: SELECT date, portfolio_name, COUNT(*) AS n FROM tracking_new.daily_portfolioreturn WHERE date = :date GROUP BY date, portfolio_name HAVING n > 1
- 通过条件: 结果集为空
- 失败含义: 存在重复行

...更多检查项...

## 统计
| 严重度 | 数量 |
|--------|------|
| BLOCKER | N |
| CRITICAL | N |
| WARNING | N |
| 总计 | N |
```

## SQL 中的变量

所有 SQL 使用 `:date` 作为日期占位符。执行时替换为实际日期即可。不硬编码任何连接信息、日期、环境。

## 检查项生成规则

对 io-flow.md 中**每个场景的每一张输出表**，按顺序生成以下检查项：

### 第一层：存在性（BLOCKER）

- 当日 COUNT(*) > 0
- 每张输出表 1 条

### 第二层：无重复（CRITICAL）

- 根据表的业务语义从 io-flow.md 推断逻辑主键（如 date + portfolio_name、date + product_code）
- GROUP BY 逻辑主键 HAVING COUNT(*) > 1，结果集应为空
- 在检查项中写明逻辑主键是什么、推断依据是什么
- 每张输出表 1 条

### 第三层：关键字段非空（WARNING）

- 从表名和 io-flow.md 的描述推断 1-2 个核心数值字段（如 return、pnl、exposure、proportion）
- 检查这些字段 IS NULL 的行数占比
- SQL: SELECT COUNT(*) AS null_cnt FROM ... WHERE date = :date AND <字段> IS NULL
- 通过条件: null_cnt = 0
- 每张输出表 1-2 条

### 第四层：跨表一致性（WARNING）

从 io-flow.md 的场景描述中提取表与表之间的逻辑关联，生成交叉校验：

**示例**（根据实际 io-flow.md 内容生成，以下仅为模式参考）：
- 同一场景内两张表的维度列表应一致（如组合列表、产品列表）
- 实时表与对应历史表的行数应一致
- 产品级别表覆盖的产品集合应相同

每条写明：左表、右表、关联逻辑、SQL、通过条件。

### 第五层：数值范围合理性（WARNING）

对收益率、比例、暴露度等字段：
- 检查绝对值是否在合理区间（如收益率 < 20%、比例在 0-1 之间）
- SQL 用 CASE WHEN 统计越界行数
- 通过条件: 越界行数 = 0

### 第六层：写入机制校验（WARNING，仅实时场景）

io-flow.md 明确标注了实时表的写入机制为"每次全删再写"：
- 检查实时表只有当日数据（不应残留历史数据）
- SQL: SELECT COUNT(DISTINCT date) AS date_cnt FROM ... 
- 通过条件: date_cnt <= 1

io-flow.md 标注了 16:00 后归档到 history_* 表：
- 对每张 realtime_* 表，检查对应 history_* 表当日行数是否与 realtime_* 一致
- 在检查项中注明"此项仅在 16:00 后适用"

## 要求

1. **严格基于 io-flow.md**：只检查文档中明确列出的输出表，不臆造表名
2. **逻辑主键必须有推断依据**：写在检查项的 `推断依据` 字段中
3. **SQL 可直接执行**：除 `:date` 占位符外，不含任何伪代码
4. **编号全局递增**：三位数字 001, 002, ...，跨场景不重置
5. **每条检查项固定字段**：类型、严重度、SQL、通过条件、失败含义
6. **末尾输出统计摘要表**
7. **覆盖所有 4 个场景**：每日更新、实时-组合、实时-产品、数据监控
