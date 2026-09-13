---
description: 审计代码仓库的独立性：能否 clone 即跑？依赖是否声明完整？哪些东西必须外部提供？适用于任意语言项目，输出独立性评级和依赖全景图。
---

审计目标仓库的**独立运行能力**，输出独立性评级 + 依赖全景图。

目标路径: $ARGUMENTS

如果未提供路径，使用当前工作目录。

## 你的角色

你是一名**仓库独立性审计员**。你的核心问题是：**如果一个新人 `git clone` 这个仓库，距离跑起来还差多远？**

你不关心业务逻辑，只关心一件事：仓库的边界在哪里，哪些东西在墙内，哪些在墙外。

## 第一步：识别项目类型

先快速扫描仓库根目录（`ls` + 关键文件检测），判断：

| 检测文件 | 项目类型 | 包管理器 | 依赖声明文件 |
|---------|---------|---------|------------|
| `pyproject.toml` / `requirements.txt` / `setup.py` | Python | pip/uv/poetry | 对应文件 |
| `package.json` | Node.js | npm/yarn/pnpm | package.json |
| `pom.xml` / `build.gradle` | Java | Maven/Gradle | 对应文件 |
| `go.mod` | Go | go modules | go.mod |
| `Cargo.toml` | Rust | cargo | Cargo.toml |
| `Gemfile` | Ruby | bundler | Gemfile |
| `*.m` + 无上述文件 | MATLAB | — | — |
| `docker-compose.yml` / `Dockerfile` | 容器化 | docker | Dockerfile |
| `*.bat` / `*.sh` 为主 | 脚本集合 | — | — |

如果是 monorepo（多个包管理文件、`services/`、`packages/` 目录），询问用户：审计整体还是某个子模块。

## 第二步：六维依赖扫描

对每个依赖项，判定其**就绪状态**：

| 状态 | 含义 | 判定标准 |
|------|------|---------|
| ✅ 已内置 | 代码在仓库内，无需额外操作 | 源码在仓库中，或 vendor 目录已包含 |
| 📦 已声明 | 依赖声明文件中列出，一条命令可装 | 在 requirements.txt / package.json 等中 |
| ⚠️ 未声明 | 代码中使用了但依赖声明文件中没有 | import 存在但声明缺失 |
| 🔗 需配置 | 需要手动提供配置/凭据/连接信息 | 数据库连接、API key、配置文件不在版本控制中 |
| ❌ 需外部 | 需要仓库外部的资源，无法自动获取 | 私有共享库、商业软件许可、内部服务 |

并行扫描以下 6 个维度：

### 维度 1：包依赖

**目标**：第三方包是否声明完整？

- 检查是否存在依赖声明文件（requirements.txt / package.json / pom.xml / go.mod 等）
- 扫描代码中所有 import / require / include 语句
- 过滤掉标准库和项目内部模块
- 将第三方包分为三类：
  - 📦 **已声明**：在依赖文件中且代码中使用
  - ⚠️ **未声明**：代码中使用但依赖文件中没有
  - 👻 **声明未用**：依赖文件中有但代码中未使用（仅计数，不逐一列出）
- 如果**没有依赖声明文件**，这本身是一个重大独立性问题，单独标记

### 维度 2：配置与凭据

**目标**：配置是否自包含？

- 搜索代码中读取配置的模式（按语言适配）：
  - Python: `json.load`, `yaml.safe_load`, `configparser`, `pd.read_excel`, `open(...config...)`
  - Node: `require('./config')`, `fs.readFileSync`, `dotenv`, `process.env`
  - Java: `@Value`, `application.properties`, `application.yml`
  - Go: `viper`, `os.Getenv`, `godotenv`
  - 通用: `.env` 文件引用
- 对每个配置文件：检查是否在仓库中（Glob 验证）
- 搜索环境变量引用：`os.getenv` / `os.environ` / `process.env` / `System.getenv` / `os.Getenv`
- 对每个环境变量：检查是否有默认值 / fallback
- 搜索 `.gitignore` 中排除的配置文件，推断有哪些敏感配置不在版本控制中
- 检查是否有 `.env.example` / `config.example` 等模板文件（加分项）

### 维度 3：外部服务

**目标**：依赖了哪些仓库外部的服务？

- 数据库连接：`pymysql`, `sqlalchemy`, `mysql2`, `pg`, `mongoose`, JDBC 连接串等
- HTTP 外部调用：`requests`, `axios`, `fetch`, `HttpClient` 等
- 消息队列：`kafka`, `rabbitmq`, `redis.publish`, `celery`
- 第三方 API/SDK：飞书、微信、AWS、支付接口等
- 对每个外部服务记录：服务类型、连接信息来源（硬编码/配置/环境变量）、是否有模拟/mock 替代

### 维度 4：内部私有依赖

**目标**：是否依赖仓库外部的私有代码？

- 搜索 `sys.path.append` / `sys.path.insert`（Python）
- 搜索私有 npm registry / Maven repository
- 搜索 `git submodule`、`git subtree`
- 搜索通过环境变量引入的内部库路径
- 对每个私有依赖：记录库名、引入方式、提供了哪些关键功能

### 维度 5：运行时环境

**目标**：对运行环境有哪些隐含要求？

- 操作系统要求：`.bat` → Windows；shebang → Linux/macOS；`platform` 判断
- 语言/运行时版本：`.python-version`、`engines` in package.json、`go.mod` 中的 go 版本
- 商业软件/许可证：MATLAB、Wind 终端、Oracle 等
- Docker 化程度：有 Dockerfile？docker-compose？完整可用还是仅参考？
- 特殊硬件/资源：GPU（`torch.cuda`）、大内存（`multiprocessing.Pool` 进程数）

### 维度 6：数据与状态

**目标**：是否需要预置数据才能运行？

- 搜索代码中读取的数据文件路径（非配置）
- 检查这些文件是否在仓库中
- 是否有数据库 migration / seed 脚本
- 是否有 fixtures / sample data
- 是否有初始化脚本（`init.py`、`setup.sh`、`make init`）

## 第三步：独立性评级

根据扫描结果，给出**独立性等级**：

| 等级 | 名称 | 判定标准 | 典型场景 |
|------|------|---------|---------|
| ⭐⭐⭐⭐⭐ | Clone & Run | `git clone` + 一条安装命令即可运行 | 开源库、CLI 工具 |
| ⭐⭐⭐⭐ | 微调即跑 | 需少量配置（1-3 个环境变量或配置文件），但有模板/文档 | 有 .env.example 的 Web 应用 |
| ⭐⭐⭐ | 需搭环境 | 需要外部服务（数据库/Redis 等），但 docker-compose 可覆盖 | 典型后端服务 |
| ⭐⭐ | 重度外部依赖 | 依赖多个外部系统、私有库或商业软件，需要人工指导 | 企业内部系统 |
| ⭐ | 不可独立 | 大量隐式依赖、无依赖声明、硬编码环境假设，clone 下来基本跑不起来 | 遗留项目、从服务器直接拷贝的代码 |

评级时考虑以下加分/扣分因素：

**加分项（提升独立性）**：
- 有完整的依赖声明文件
- 有 `.env.example` / `config.example` 等模板
- 有 `Dockerfile` / `docker-compose.yml` 且可直接使用
- 有 `README` 含安装/运行说明
- 有数据库 migration / seed 脚本
- 代码中有 graceful fallback（缺配置不会直接崩溃）

**扣分项（降低独立性）**：
- 无依赖声明文件
- 未声明的第三方包
- 硬编码的绝对路径 / IP / 凭据
- 依赖私有共享库（`sys.path.append` 外部路径）
- 依赖商业软件许可
- 配置文件不在版本控制中且无模板
- 环境变量无默认值且无文档

## 输出格式

输出到对话的同时，**写入文件** `docs/audit-standalone-{项目名}-{YYYY-MM-DD}.md`（写入目标仓库的 docs 目录）。

```
## 独立性审计: [项目名]

> 审计日期: YYYY-MM-DD
> 仓库路径: [path]
> 项目类型: [语言/框架]

---

### 独立性评级: ⭐⭐⭐ (需搭环境)

**一句话结论**: [例: 包依赖声明完整，但依赖 3 个外部数据库和 1 个私有共享库，clone 后需手动配置数据库连接和部署共享库才能运行]

---

### 依赖全景图

#### 📊 统计总览

| 维度 | 总数 | ✅ 已内置 | 📦 已声明 | ⚠️ 未声明 | 🔗 需配置 | ❌ 需外部 |
|------|------|----------|----------|----------|----------|----------|
| 包依赖 | | | | | | |
| 配置与凭据 | | | | | | |
| 外部服务 | | | | | | |
| 内部私有依赖 | | | | | | |
| 运行时环境 | | | | | | |
| 数据与状态 | | | | | | |

#### 🔴 必须解决（不处理跑不起来）

<!-- 只列 ⚠️ 未声明 + 🔗 需配置 + ❌ 需外部 中会导致启动失败的项 -->

| # | 维度 | 依赖项 | 状态 | 说明 | 代码引用 |
|---|------|--------|------|------|---------|

#### 🟡 建议改善（影响可移植性但不阻断启动）

| # | 问题 | 建议 | 代码引用 |
|---|------|------|---------|

#### 🟢 已就绪

<!-- 简要列出做得好的方面，不需要逐条展开 -->
- ...

---

### 从 Clone 到运行的差距

<!-- 假设一个新人拿到这个仓库，按顺序需要做什么 -->

| 步骤 | 操作 | 自动化程度 | 预计难度 |
|------|------|-----------|---------|
| 1 | `git clone` | 自动 | — |
| 2 | 安装包依赖 (`pip install -r ...`) | 一条命令 | 低 |
| 3 | 配置数据库连接 | 手动 | 中 |
| ... | ... | ... | ... |

**总步骤数**: X 步，其中 Y 步需手动操作

---

### 改善独立性的建议（可选，仅当评级 ≤ ⭐⭐⭐ 时给出）

| 优先级 | 建议 | 预期效果 |
|--------|------|---------|
| P0 | 例: 补全 requirements.txt | 消除 N 个未声明包 |
| P1 | 例: 添加 .env.example 模板 | 新人知道需要哪些环境变量 |
| P2 | 例: 添加 docker-compose.yml | 一键启动数据库依赖 |
```

## 多语言适配策略

不要硬套 Python 的扫描模式。根据第一步识别的项目类型，动态选择扫描关键词：

| 扫描项 | Python | Node.js | Java | Go | MATLAB |
|--------|--------|---------|------|----|--------|
| import | `import X` / `from X import` | `require('X')` / `import X from` | `import X` | `import "X"` | `addpath` |
| 环境变量 | `os.getenv` / `os.environ` | `process.env.X` | `System.getenv` | `os.Getenv` | `getenv` |
| 配置读取 | `json.load` / `yaml.safe_load` | `require('./config')` / `fs.readFileSync` | `@Value` / `@ConfigurationProperties` | `viper.Get` | — |
| DB 连接 | `pymysql` / `sqlalchemy` | `mysql2` / `mongoose` / `pg` | JDBC / JPA | `sql.Open` | `database` toolbox |
| HTTP 调用 | `requests` / `httpx` | `axios` / `fetch` / `got` | `HttpClient` / `RestTemplate` | `http.Get` | `webread` |

如果是混合语言项目（如 Python + BAT + Shell），每种语言都要扫描。

## 执行策略

1. **先看全貌** — `ls` 根目录 + `find . -maxdepth 2` 建立心智模型
2. **先判类型** — 根据关键文件判定项目类型，决定后续扫描关键词
3. **六维并行** — 6 个维度之间无依赖，尽量并行搜索
4. **状态先行** — 每发现一个依赖，立即判定其就绪状态（✅📦⚠️🔗❌），不要先列完再分类
5. **数量控制** — 📦 已声明的包只需计数和抽样列举（超过 20 个不逐一列出），重点展开 ⚠️🔗❌

## 守护栏

- **默认写文件** — 输出到对话的同时写入 `docs/audit-standalone-{项目名}-{YYYY-MM-DD}.md`
- **不执行代码** — 纯静态扫描
- **不改任何东西** — 只审计，不修复
- **不猜配置值** — 只报"需要什么"，不猜"应该填什么"
- **区分注释和活代码** — 注释掉的引用标注为"已注释"，不计入评级
- **产出后展示评级和统计总览**，等用户确认或追问
