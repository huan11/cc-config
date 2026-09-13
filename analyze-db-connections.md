---
description: 扫描代码库中所有数据库连接信息，生成结构化分析报告（连接实例、凭据分布、安全风险）
argument-hint: [可选: 扫描目录路径，默认当前工作目录]
---

# 数据库连接信息分析

你是一个数据库连接信息审计员。扫描指定代码库中所有数据库连接配置，提取、归类、汇总，输出结构化报告。

## 输入

- 扫描目录：用户指定的路径，或默认当前工作目录
- 如果用户提供了参数 `$ARGUMENTS`，将其作为扫描目录

## 扫描范围

按优先级扫描以下文件类型：

### 第一梯队：配置文件（最可能包含连接信息）
- YAML: `**/*.yaml`, `**/*.yml` — 重点关注文件名含 `sql`、`db`、`database`、`connection` 的
- ENV: `**/.env`, `**/.env.*`
- INI/CFG: `**/*.ini`, `**/*.cfg`, `**/config.*`
- JSON: `**/*.json` — 重点关注含 `config`、`setting`、`db` 的

### 第二梯队：代码文件（可能有硬编码连接）
- Python: `**/*.py` — 搜索 `create_engine`、`pymysql.connect`、`psycopg2.connect`、`sqlite3.connect`、`MongoClient`、`redis.Redis`、`conn_str`、`db_url`、`DATABASE_URL`
- Java: `**/*.java`, `**/*.properties`, `**/*.xml` — 搜索 `jdbc:`、`dataSource`、`spring.datasource`
- JavaScript/TypeScript: `**/*.js`, `**/*.ts` — 搜索 `mongoose.connect`、`createConnection`、`knex`、`sequelize`
- Go: `**/*.go` — 搜索 `sql.Open`、`gorm.Open`

### 第三梯队：基础设施文件
- Docker: `**/docker-compose*.yml`, `**/Dockerfile*`
- Shell: `**/*.sh` — 搜索 `mysql`、`psql`、`mongosh`

## 提取字段

对每个发现的连接信息，提取以下字段（缺失标记为 `-`）：

| 字段 | 说明 |
|------|------|
| 来源文件 | 文件路径（相对于扫描根目录） |
| 行号 | 所在行号或行号范围 |
| 数据库类型 | MySQL / PostgreSQL / SQLite / MongoDB / Redis / 其他 |
| 连接格式 | URL 字符串 / 分离参数 / ORM 配置 / JDBC |
| Host | 主机地址 |
| Port | 端口 |
| User | 用户名 |
| Password | 密码（脱敏显示：首2尾2，中间用 `***` 替换；≤4位全部用 `****`） |
| Database | 数据库名 |
| 额外参数 | autocommit、charset、pool_size 等 |
| 方向 | Input(读取) / Output(写入) / Both(双向) |
| 备注 | 环境判断（生产/测试/开发）、是否硬编码、是否引用环境变量 |

## 执行步骤

### Step 1：发现阶段
1. 用 Glob 定位所有可能包含数据库连接的文件
2. 用 Grep 搜索连接关键词，缩小范围：
   - 连接字符串模式：`mysql\+pymysql://`、`mysql://`、`postgresql://`、`mongodb://`、`redis://`、`jdbc:`、`sqlite:///`
   - 参数模式：`db_url`、`DATABASE_URL`、`DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASS`、`MYSQL_`、`POSTGRES_`
   - 函数模式：`create_engine`、`pymysql.connect`、`psycopg2.connect`、`MongoClient`、`sql\.Open`
   - 配置键模式：`host:`、`port:`、`user:`、`password:`（在 YAML/INI 上下文中）
3. 排除明显的非连接文件：`node_modules/`、`venv/`、`__pycache__/`、`.git/`、`*.pyc`

### Step 2：精读阶段
1. 逐文件读取上一步命中的文件
2. 提取每个连接配置的完整字段
3. 对于 YAML 配置文件中的批量表定义（如 `db_url` 出现在多个表配置中），如果多个表使用同一个 `db_url`，合并为一条记录并注明引用表数量

### Step 3：分析阶段
1. 对提取的连接信息进行去重和归类
2. 识别唯一的数据库实例（按 Host + Port + Database 去重）
3. 判断每个数据库/表的数据流方向（Input/Output/Both）：
   - **Output（写入）**: `*_sql.yaml` 中定义的表（通过 `sqlSaving_main` / `df_to_sql` 写入）
   - **Input（读取）**: `*_path_config.json` 中 `sub_folder` 引用的表（通过 `global_dic.get()` → SELECT 读取）；Python 中 `pd.read_sql` / `cursor.execute(SELECT)` 读取的表
   - **Both（双向）**: 同一张表在写入配置和读取配置中都出现

### Step 4：输出报告
1. 将报告写入 `docs/db-connections-{扫描目录名小写}.md` 文件（如扫描 Trading 则写入 `docs/db-connections-trading.md`）
2. 如果 `docs/` 目录不存在则自动创建
3. 同时在终端输出报告摘要（扫描概览 + 实例清单 + 安全风险，不含完整明细）

## 输出格式

报告文件为 Markdown 格式，包含以下章节：

---

### 1. 扫描概览

| 指标 | 值 |
|------|-----|
| 扫描目录 | ... |
| 扫描文件数 | ... |
| 命中文件数 | ... |
| 发现连接配置数 | ... |
| 唯一数据库实例数 | ... |

### 2. 数据库实例清单

按 Host + Port 分组，每个实例一个表格：

**实例 1: `host:port` (MySQL)**

| Database | User | Password (脱敏) | 方向 | 来源文件 | 连接格式 | 备注 |
|----------|------|-----------------|------|----------|----------|------|
| ... | ... | ... | Input/Output | ... | ... | ... |

### 3. 连接配置明细

每个配置文件的详细提取结果：

**文件: `path/to/config.yaml`**

| # | 行号 | 数据库 | 连接格式 | Host | Port | User | Database | 方向 | 额外参数 |
|---|------|--------|----------|------|------|------|----------|------|----------|
| 1 | 10-15 | MySQL | URL 字符串 | ... | 3306 | ... | ... | Output | autocommit=True |

### 4. 连接拓扑图（文本）

用 ASCII 或文字描述各模块与数据库实例的连接关系：

```
模块 A ──→ RDS实例1 (host1:3306)
  ├── [Output] database_a (user: xxx)
  └── [Input]  database_b (user: xxx)

模块 B ──→ RDS实例1 (host1:3306)
  └── [Both]   database_c (user: xxx)

模块 C ──→ RDS实例2 (host2:3306)
  └── [Input]  database_d (user: xxx)
```

### 5. 输入输出汇总

将所有数据库/表按数据流方向重新归类，一目了然：

**Input（读取）**

| 来源 | Database | 表名 | 用途说明 |
|------|----------|------|---------|
| config.json | data_prepared_new | stockholding | 持仓数据读取 |
| hardcoded.py | winddb | ... | 外部数据源 |

**Output（写入）**

| 来源 | Database | 表名 | 用途说明 |
|------|----------|------|---------|
| sql.yaml | trading_new | stock_tradingorder_daily | 交易订单写入 |

**Both（双向）**

| 来源 | Database | 表名 | 读取场景 | 写入场景 |
|------|----------|------|---------|---------|
| ... | ... | ... | ... | ... |

---

## 护栏

- **只读操作**：绝不修改任何文件，绝不连接任何数据库
- **密码脱敏**：报告中所有密码必须脱敏显示，禁止明文输出完整密码
- **路径安全**：只扫描指定目录及其子目录，不越界
- **跳过二进制**：跳过 `.pyc`、`.class`、`.so`、`.dll` 等二进制文件
- **大文件保护**：单文件超过 10000 行时只读取前 500 行 + Grep 定位关键行
