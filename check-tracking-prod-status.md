---
description: 检查 Tracking 系统生产环境的运行状态：每个场景的输入齐不齐、输出写了没、有没有异常。
argument-hint: <数据库连接 host:port:user:pass> [日期 YYYY-MM-DD]
---

连接 Tracking 生产数据库，逐场景检查当日运行状态。

## 参数

- `$ARGUMENTS` 格式：`host:port:user:pass [日期]`
- 日期可选，默认今日
- 连接信息不足时询问

## 场景定义

Tracking 系统有 4 个场景，按执行时序排列：

| 场景 | 入口 | 执行时机 |
|---|---|---|
| 实时-组合 | `tracking_realtime_main_portfolio()` | 盘中循环，9:35-15:05 |
| 实时-产品 | `tracking_realtime_main_product()` | 盘中循环，9:35-15:05 |
| 归档 | `historySql_saving.historySql_main()` | 16:00 后由实时场景触发 |
| 每日更新 | `tracking_daily_update_main()` | 夜间 ~23:30 |

## 检查步骤

### Step 1: 检查输入表

**注意**：输入表在 `data_prepared_new` 和 `portfolio_new` 库中，日期字段名各表不同，先用 `SHOW COLUMNS` 确认。

**全局必须**（缺了所有场景跑不了）：

| 库 | 表 | 用途 |
|---|---|---|
| rz_hfdb 或行情库 | 行情数据 | 股票/期货/期权/ETF/可转债/指数收盘价 |

**实时-组合必须**：

| 库 | 表 |
|---|---|
| portfolio_new | portfolio |
| portfolio_new | product_weight |
| portfolio_new | portfolio_info |

**实时-产品必须**：

| 库 | 表 |
|---|---|
| data_prepared_new | stockholding_temp |
| data_prepared_new | futureholding_temp |
| data_prepared_new | data_l4holding |
| data_prepared_new | data_l4info |
| portfolio_new | portfolioinfo_product |

**每日更新额外需要**：

| 库 | 表 |
|---|---|
| data_prepared_new | stockholding |
| data_prepared_new | futureholding |

**可选**（缺了部分输出表为空）：

| 库 | 表 | 缺失影响 |
|---|---|---|
| data_prepared_new | data_factorexposure | daily_portfoliofactor / daily_productfactor 为空 |
| data_prepared_new | data_factorreturn | 同上 |
| data_prepared_new | data_score | scoresplit 为空 |

**输入缺失 → 标红并标注影响范围，继续检查其他场景。**

### Step 2: 检查实时-组合输出

所有输出在 `tracking_new` 库，日期字段为 `valuation_date`。

**realtime 表**（盘中每次全删再写，9:00-9:35 会被清空）：

| 表 | 正常行数参考 |
|---|---|
| realtime_portfolioreturn | ~41 |
| realtime_productstockreturn | ~9 |
| realtime_portfoliosplit | ~84 |
| realtime_scoresplit | ~116 |
| realtime_portfoliocontribution | ~17 |

查询（不带日期过滤，realtime 表只有当日数据）：
```sql
SELECT '<表名>' AS tbl, COUNT(*) AS cnt, 
       MIN(update_time) AS min_update, MAX(update_time) AS max_update 
FROM tracking_new.<表名>;
```

判定逻辑：
- 9:00-9:35 → 为空正常（正在清表）
- 9:35-15:05 → 应有数据，且 max_update 在最近 5 分钟内
- 15:05 后 → 应有数据，max_update 在 15:00 附近
- 次日 9:00 后 → 已被清空，只能看 history

### Step 3: 检查实时-产品输出

**realtime 表**（盘中每次全删再写，9:00-9:30 会被清空）：

| 表 | 正常行数参考 |
|---|---|
| realtime_proinfo | ~486（54行/产品 x 9产品） |
| realtime_futureoptionholding | ~17-26 |
| realtime_holdingchanging | ~1750 |

查询和判定逻辑同 Step 2。

### Step 4: 检查归档

**history 表**（16:00 后从 realtime 复制）：

| 表 | 对应 realtime 表 |
|---|---|
| history_portfolioreturn | realtime_portfolioreturn |
| history_productstockreturn | realtime_productstockreturn |
| history_portfoliosplit | realtime_portfoliosplit |
| history_scoresplit | realtime_scoresplit |
| history_portfoliocontribution | realtime_portfoliocontribution |
| history_proinfo | realtime_proinfo |
| history_futureoptionholding | realtime_futureoptionholding |
| history_holdingchanging | realtime_holdingchanging |

```sql
SELECT '<表名>' AS tbl, COUNT(*) AS cnt,
       MIN(update_time) AS min_update, MAX(update_time) AS max_update
FROM tracking_new.<表名>
WHERE valuation_date = '<目标日期>';
```

判定逻辑：
- 16:00 前 → 未归档正常
- 16:00 后 → 应有数据，行数应与 realtime 相近

### Step 5: 检查每日更新

**daily 表**（夜间 ~23:30 写入，回溯近 3 个工作日）：

| 表 | 来源 | 正常行数参考 |
|---|---|---|
| daily_portfolioreturn | portfolio_tracking | ~49 |
| daily_productstockreturn | portfolio_tracking | ~9 |
| daily_portfoliosplit | Split_main | ~84 |
| daily_scoresplit | Split_main | ~117 |
| daily_portfoliofactor | Exposure_main | 依因子数 |
| daily_weightdifference | weight_analysis | 依组合数 |
| daily_proinfo | product_tracking | ~486 |
| daily_futureoptionholding | product_tracking | ~17-26 |
| daily_holdingchanging | product_tracking | ~1750 |
| daily_productfactor | exposure_tracking | 依因子数 |
| daily_productHoldingSplit | partial_analysis2 | 依产品数 |

```sql
SELECT '<表名>' AS tbl, COUNT(*) AS cnt,
       MIN(update_time) AS min_update, MAX(update_time) AS max_update
FROM tracking_new.<表名>
WHERE valuation_date = '<目标日期>';
```

判定逻辑：
- 23:30 前 → 未执行正常
- 23:30 后 → 前 4 张（组合级）应有数据
- **已知问题**：后 7 张（产品级）自 2026-01-26 起断更，如仍为空则标注"已知断更"而非"异常"

## 输出

保存到 `docs/tracking-prod-status-<YYYYMMDD-HHmmss>.md`。

报告结构：

> # Tracking 生产状态: <目标日期>
> 检查时间: <当前时间>
> 
> ## 输入状态
> | 级别 | 库.表 | 有数据？ | 行数 |
> ...
>
> ## 实时-组合
> | 表 | 行数 | 最后更新 | 状态 |
> ...
>
> ## 实时-产品
> | 表 | 行数 | 最后更新 | 状态 |
> ...
>
> ## 归档
> | 表 | 行数 | 归档时间 | 状态 |
> ...
>
> ## 每日更新
> | 表 | 行数 | 最后更新 | 状态 |
> ...
>
> ## 结论
> | 场景 | 状态 | 备注 |
> ...

## 要求

1. **只执行 SELECT**
2. **根据当前时间判定状态** — 同样是空，9:00 和 17:00 查到的含义不同
3. **已知问题标注"已知断更"** — 不要每次都当新问题报
4. **行数参考值来自 2026-04-09 基准** — 如果偏差超过 50% 要标注
