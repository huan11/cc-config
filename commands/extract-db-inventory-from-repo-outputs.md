---
description: 从 repo-outputs 和 SQL 配置文件中提取数据库清单（连接信息、库、表、字段、逻辑键），生成独立的数据库产物文档。
argument-hint: [docs/repo-outputs-*.md 路径，不指定则自动查找]
---

从已有的 repo-outputs 文档出发，交叉引用 SQL 配置文件，提取并汇总项目的全部数据库产物信息。

## 输入

- `$ARGUMENTS`：repo-outputs 文件路径。不指定则在 `docs/` 下查找 `repo-outputs-*.md`。

## 你的角色

你是一名**数据库资产盘点员**。你的任务是回答：**这个项目往哪些数据库的哪些表写了什么数据？**

你不关心文件产物、不关心业务逻辑，只关心数据库写入。

## 执行步骤

### Step 1: 定位信息源

需要三类文件，全部通过搜索定位（不要假设路径）：

| 信息源 | 搜索方式 | 提供什么 |
|-------|---------|---------|
| repo-outputs | 用户指定或 `docs/repo-outputs-*.md` | 表清单、逻辑名、写入模式、所属模块 |
| SQL 写入配置 | Grep 搜索 `table_name` + `db_url` 的 YAML/JSON 文件 | 逻辑名 → 实际表名映射、db_url（含库名）、schema、primary_keys |
| SQL 连接配置 | Grep 搜索 `host` + `port` + `database` 的 YAML/JSON 文件 | 真实连接参数（host、port、user、database） |

如果找不到某类文件，在输出中标注"未找到"，不要编造。

### Step 2: 提取连接信息

从 SQL 连接配置中提取：
- host
- port
- database（默认库）
- user
- **password 脱敏处理**：只显示 `***`，不输出明文密码

从 SQL 写入配置的 `db_url` 字段中提取所有出现过的库名（如 `data_prepared_new`、`portfolio_new`），去重汇总。

### Step 3: 构建表清单

对 SQL 写入配置中的每个逻辑名，提取：

| 字段 | 来源 |
|------|------|
| 逻辑名 | YAML 的顶层 key |
| 实际表名 | `table_name` 字段 |
| **表注释** | **从逻辑名、字段含义、所属模块综合推断的一句话中文说明（如"指数日行情数据"）** |
| 目标库 | 从 `db_url` 中解析出的数据库名 |
| 逻辑键 | `private_keys` 字段（应用层 delete 条件，**不一定是数据库 PRIMARY KEY**，字段名用"逻辑键"标注） |
| 字段列表 | `schema` 的所有 key |
| 字段类型 | `schema` 中每个 key 的 `type` |
| 写入模式 | 从 repo-outputs 交叉引用（delete+insert / append） |
| 所属模块 | 从 repo-outputs 交叉引用 |

### Step 4: 合并多对一映射

多个逻辑名映射到同一张物理表时（如 M1M2/Shibor/CPI → `data_macro`）：
- 按物理表合并为一条
- 逻辑名全部列出
- schema 取并集（通常相同）

### Step 5: 输出

写入 `docs/db-inventory-[项目名].md`。

## 输出格式

```markdown
# 数据库产物清单: [项目名]

> 提取日期: YYYY-MM-DD
> 信息来源:
> - repo-outputs: [文件路径]
> - SQL 写入配置: [文件路径]
> - SQL 连接配置: [文件路径]

---

## 一、连接信息

| 属性 | 值 |
|------|-----|
| Host | xxx |
| Port | 3306 |
| User | xxx |
| Password | *** |
| 涉及数据库 | db1, db2 |

---

## 二、数据库总览

| 数据库 | 表数量 | 用途概述 |
|-------|--------|---------|

---

## 三、表清单

### 库: data_prepared_new

#### 1. data_index — 指数日行情数据

| 属性 | 值 |
|------|-----|
| 逻辑名 | indexData |
| 表注释 | 指数日行情数据 |
| 写入模式 | delete+insert |
| 所属模块 | MktData |
| 逻辑键 (YAML private_keys) | valuation_date, code |

**字段:**

| # | 字段名 | 类型 |
|---|--------|------|
| 1 | valuation_date | String(50) |
| 2 | code | String(50) |
| ... | ... | ... |

---

<!-- 对共享物理表特别标注 -->

#### 11. data_macro — 宏观经济指标数据 (共享表)

> 以下 9 个逻辑名共用此表，通过 `organization` 字段区分：
> M1M2, Shibor, CPI, PPI, PMI, ChinaGovernmentBonds, ChinaDevelopmentBankBonds, ChinaMediumTermNotes, SocialFinance

| 属性 | 值 |
|------|-----|
| 逻辑名 | M1M2, Shibor, CPI, PPI, PMI, ... |
| 表注释 | 宏观经济指标数据（M1M2/Shibor/CPI/PPI 等 9 类共用） |
| 写入模式 | append |
| 所属模块 | MacroData |
| 逻辑键 (YAML private_keys) | valuation_date, type, name |

---

### 库: portfolio_new

#### ...

---

## 四、数据检查配置

<!-- 如果找到 database_check.yaml 或类似文件，列出各表的检查模式 -->

| 检查模式 | 检查维度 | 涉及表 |
|---------|---------|--------|
| mode1 | valuation_date | data_index, data_stock, ... |
| mode2 | valuation_date + organization | data_vix, ... |

---

## 五、注意事项

<!-- 列出发现的问题，例如: -->
<!-- - 密码明文存储在配置文件中 -->
<!-- - db_url 中的 host/port 是占位符（username:password@host:prot） -->
<!-- - 某些表在 repo-outputs 中有但 YAML 中没有，或反之 -->
```

## 守护栏

- **只写 `docs/db-inventory-[项目名].md`**，不修改任何已有文件
- **密码必须脱敏** — 输出中不允许出现明文密码
- **不连接数据库** — 纯静态提取，不执行任何 SQL
- **不编造字段** — 只输出配置文件中实际存在的信息
- **交叉校验** — repo-outputs 和 YAML 配置中的表如果对不上，在"注意事项"中标注差异
