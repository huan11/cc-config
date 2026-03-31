审查 MATLAB 函数/脚本，按 8 大类 50+ 检查项逐项检查，输出问题清单。

参数：`/review <file.m> [depth] [--focus cat1,cat2] [--sub full|interface] [--fix] [--diff [ref]]`

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `<file.m>` | 必填 | 目标文件路径 |
| `depth` | `1` | 下游调用链深度：`1/2/3/all`。只展开项目 `code/` 内 .m 文件，跳过 MATLAB 内置和 toolbox |
| `--focus` | 全部 | 只跑指定类别：`call,error,data,sql,persist,env,test,parallel` |
| `--sub` | `full` | depth>=2 时子函数检查模式：`full`=完整7类检查 / `interface`=只查签名兼容 |
| `--fix` | 关闭 | 审查完自动进入 `/fix` 流程（只处理 P0+P1） |
| `--diff` | 关闭 | 只审查 git diff 涉及的改动行及上下文，可指定 ref（如 `--diff HEAD~1`） |

## 第一步：文件识别

读取目标文件，识别类型并标记特殊属性：

| 类型 | 识别方式 | 额外检查 |
|------|----------|----------|
| classdef | 文件开头 `classdef` | O4 双路径同步（PE/PB/TAT/PCF）、修改后需 `clear classes` |
| script | 无 `function` 声明 | 全局变量污染、路径依赖 |
| function | `function` 开头 | 签名兼容性、nargin 默认值 |
| 混合体 | script + 底部 local functions | 函数缓存需 `clear functions` |

## 第二步：调用链展开（depth>=2 时）

1. 识别目标文件中调用的所有函数/方法
2. 在项目 `code/` 目录内 glob `**/<funcName>.m`，找到的才展开
3. 找不到的视为 MATLAB 内置，跳过
4. 按 depth 递归展开，记录调用链树

## 第三步：逐类检查

对目标文件（及展开的子文件）按以下 8 类逐项检查。根据文件内容智能筛选：含 `fetch(` 或 SQL 字符串才检查 sql 类，含 `save(`/`writetable`/`DELETE` 才检查 persist 类，含 `parfeval`/`parfor`/`parpool` 才检查 parallel 类，不适用的标 N/A。

### 类别 1：调用点和边界条件（call）

| # | 检查项 | 说明 |
|---|--------|------|
| 1.1 | 所有调用点签名一致 | 函数签名改了，调用方必须同步 |
| 1.2 | 可选参数有默认值 | `nargin < N` 的 N 正确，且给安全默认值 |
| 1.3 | 标量 vs 向量 | 输入可能是标量或向量，行为是否一致 |
| 1.4 | 空输入保护 | `[]`、`''`、`{}`、空 table(0行) 每种都保护 |
| 1.5 | O4 双路径同步 | PE/PB/TAT/PCF 的 classdef + genBatch 必须同改 |
| 1.6 | 入口变体全同步 | backtest_top_func / backtest_top / compSig×2 |
| 1.7 | classdef 缓存 | 改 .m 后需 `clear classes` |
| 1.8 | 函数缓存 | 脚本内 local function 改后需 `clear functions` |
| 1.9 | 同逻辑多副本同步 | 同一逻辑存在 N 份副本时，修一处必须同步全部 |
| 1.10 | 参数端到端传递 | 新增参数须追踪从入口到消费层每一步的传递和消费 |
| 1.11 | 平行入口语义一致 | 同一功能的所有入口必须产出语义等价的结果（见下方说明） |
| 1.12 | 多阶段时序依赖 | Phase N 的输出若被 Phase N+1 消费，不能在 Phase 1 预计算并固化（见下方说明） |

**1.11 平行入口检查方法：** depth=all 时，识别目标文件实现的核心功能（如"多日优化"、"批量调度"），grep 项目内同功能的其他入口文件（如 `run_optimizer` vs `run_optimizer_json`、`batch_run` vs `run_batch`），比对关键数据流（如 yesterday_path、shared_cache、status 传播）的处理是否语义一致。不一致则标 P0/P1。

**1.12 多阶段时序检查方法：** 当函数采用"先全部准备，再全部执行"的两阶段架构时，检查 Phase 1 是否依赖了 Phase 2 才会产出的文件/数据。典型场景：Phase 1 查找 `optimized_weight.csv` 但该文件在 Phase 2 优化后才生成 → yesterday_path 被固化为空。

### 类别 2：错误处理机制（error）

| # | 检查项 | 说明 |
|---|--------|------|
| 2.1 | catch 不吞异常 | catch 至少 fprintf/warning 输出错误信息 |
| 2.2 | fallback 不降级数据质量 | 无正确数据时 error，不静默用错误数据 |
| 2.3 | 除法防零 | ÷0→NaN，Inf 视同 NaN |
| 2.4 | DB 连接失效保护 | isempty(conn) 检查后重连或 error |
| 2.5 | 文件不存在 ≠ 数据为空 | `exist(f,'file')~=2` 和 `isempty(data)` 分别处理 |
| 2.6 | warning vs error 选择 | 可恢复用 warning，不可恢复用 error |
| 2.7 | 错误消息含上下文 | 打印文件路径、日期、变量名 |
| 2.8 | Future.Error 诊断 | parfeval catch 块须打印 `F.Error.message` + `F.Error.stack`，否则错误信息丢失 |
| 2.9 | 状态端到端传播 | success/partial/failed 等状态从计算层到存储层每层正确传播 |

### 类别 3：数据格式与完整性（data）

| # | 检查项 | 说明 |
|---|--------|------|
| 3.1 | 列名统一 | date vs dt、factorName vs value，显式重命名 |
| 3.2 | 数据类型统一 | double/cell/string/char，iscell 再 str2double |
| 3.3 | dataset vs table | isa(x,'dataset') → dataset2table(x) 桥接 |
| 3.4 | 日期格式 yyyymmdd numeric double | 不是 datenum、datetime、string |
| 3.5 | qtid 格式一致 | 000001.SZ / 600519.SH / 688001.SH，cell string |
| 3.6 | vertcat 列对齐 | 合并前列名、列数、列类型完全一致 |
| 3.7 | 嵌套 cell 展平 | iscell(ds.qtid{1}) → vertcat(ds.qtid{:}) |
| 3.8 | 重复行检测 | JOIN 后 GROUP BY 或 unique 去重 |
| 3.9 | NaN/Inf 清洗 | 输出前 Inf→NaN，计算用 'omitnan' |
| 3.10 | 覆盖验证三件套 | 行数(~4500-5500) + STIB(~600) + 重复qtid(=0) |
| 3.11 | 派生序列显式对齐 | 差分/滚动序列用 `[NaN; vals]` 补齐，禁止 `dates(2:end)` 隐式截断 |
| 3.12 | 同构变量族整体修 | 修 `rolling_ir` 时须搜 `rolling_` 前缀的所有同族变量 |
| 3.13 | 跨模块同指标一致 | 同一指标在不同模块须用相同时间粒度和计算口径 |

### 类别 4：SQL 专项（sql）— 仅含 SQL 的文件

| # | 检查项 | 说明 |
|---|--------|------|
| 4.1 | BOD 时间戳严格 `<` | InfoPublDate < dt（不含当日） |
| 4.2 | ListedSector 板块分离 | sqlMain(1,2,6,8) + sqlStib(=7) |
| 4.3 | CompanyCode JOIN 去重 | GROUP BY qtid + 聚合函数 |
| 4.4 | JDBC alias 函数包裹 | IFNULL(col, NULL) AS alias |
| 4.5 | MySQL 5.7 兼容 | 无 ROW_NUMBER / CTE |
| 4.6 | 易错字段名勿改 | OperatingReenue(缺v)、LongDebtToWorkCapital(主板多ing) |
| 4.7 | STIB TTM 公式 | Q4直取；Q1/Q2/Q3 = 当期累计+上年年报-上年同期累计 |
| 4.8 | 批量查询逐日匹配 | 不能用 endDate 查一次复用 |
| 4.9 | LEFT JOIN + WHERE 降级 | WHERE 引用右表列会静默降级为 INNER JOIN，条件应放 ON |
| 4.10 | SQL 除法防零 | CASE WHEN col>0 THEN x/col ELSE NULL END |

### 类别 5：持久化与幂等性（persist）— 仅含文件/DB 写入的文件

| # | 检查项 | 说明 |
|---|--------|------|
| 5.1 | MAT 增量替换 | 加载→删区间→追加→排序→保存，禁止直接 save 覆盖 |
| 5.2 | DB 写入幂等 | DELETE WHERE date BETWEEN + INSERT |
| 5.3 | load() 不污染 workspace | S = load(f); data = S.(varName) |
| 5.4 | 覆盖范围逐日验证 | 不能只查 min/max，要 ismember 逐日验证 |
| 5.5 | 先删后插无条件执行 | DELETE 不与"有数据才执行"耦合，否则旧数据残留 |
| 5.6 | 查询不假设前置状态 | `WHERE status=0` 阻止重跑，条件须兼容重跑场景 |

### 类别 6：MATLAB 环境特性（env）

| # | 检查项 | 说明 |
|---|--------|------|
| 6.1 | str2double 对 char 矩阵返回标量 | 多行 char 必须 cellstr() 包裹 |
| 6.2 | datestr 返回 char 矩阵 | 多日期返回 N×8 char，不是 cell |
| 6.3 | -batch 模式 stdout 缓冲 | 用 diary 或 fprintf flush |
| 6.4 | 路径用 fullfile() | 不硬编码 \ 或 / |
| 6.5 | fetch(conn,sql) 替代 exec+cursor | 新 API 直接返回 table |
| 6.6 | ismember 类型一致 | cell 和 double 不能混用 |
| 6.7 | 变量名不遮蔽内置函数 | 不用 dir/path/table 做变量名 |
| 6.8 | min([])/max([]) 返回空 | 空数组操作前检查 isempty |
| 6.9 | nanmean/nanstd 已废弃 | 改用 mean(...,'omitnan') |
| 6.10 | -batch 工作目录 | `matlab -batch` 须显式 cd 到目标目录，否则找不到函数 |
| 6.11 | exportgraphics 替代 saveas | PDF 生成用 `exportgraphics`，`saveas` 格式不可控 |
| 6.12 | -batch stdout 全缓冲 | 进度检测须用输出文件而非 stdout |

### 类别 7：测试验证策略（test）

| # | 检查项 | 说明 |
|---|--------|------|
| 7.1 | 正常路径 | 标准输入能正确产出 |
| 7.2 | 边界值 | 空输入、单元素、超大范围 |
| 7.3 | 类型变体 | double / cell / string / dataset / table |
| 7.4 | 幂等性 | 跑两次结果一致 |
| 7.5 | 交叉验证 | 两个数据源同一指标对比 |
| 7.6 | 修复清零 | Grep 所有同模式实例，全部修完 |
| 7.7 | fprintf 验证代码路径 | 看输出内容确认走了正确分支 |
| 7.8 | 修之前先验证 | 审计/报告发现可能误判，追踪数据流确认后再修 |
| 7.9 | 跨模块搬运先评估 | 一个模块的改动搬到另一模块前，先分析在新场景下是否适用 |

### 类别 8：并行计算（parallel）— 仅含 parfeval/parfor/parpool 的文件

| # | 检查项 | 说明 |
|---|--------|------|
| 8.1 | fetchNext 超时处理 | `fetchNext(futures, timeout)` 超时返回空，未检查则后续用空索引崩溃 |
| 8.2 | local function 作用域 | local function **不能**访问父函数 workspace 变量，必须通过参数传递 |
| 8.3 | parpool 生命周期 | 用完须 `delete(pool)` 或设 `IdleTimeout`，否则残留占资源 |
| 8.4 | worker 日志不可见 | parfeval worker 的 fprintf 不传回主进程，错误诊断须靠 `Future.Error` |
| 8.5 | onCleanup 边界 | 仅在 error/Ctrl+C 触发，外部 kill 进程不触发，需多层防御 |
| 8.6 | 缓存 key 跨文件一致 | 多文件共享缓存时，key 拼接格式必须完全一致 |

## 第四步：严重度分级

| 级别 | 含义 | 例子 |
|------|------|------|
| ❌ P0 | 数据错误/静默丢数据 | 空 catch 吞异常、除零未保护、GROUP BY 缺失 |
| ⚠️ P1 | 可能出错但未必触发 | nargin 无默认值、类型未检查、vertcat 未验证列 |
| 💡 P2 | 代码规范/可维护性 | 命名不一致、缺错误消息上下文、废弃 API |

## 第五步：输出

按 P0→P1→P2 排序输出检查结果，格式如下：

```
## /review <file.m> (depth=N)

### <file.m>（层 1）
| # | 检查项 | 严重度 | 结果 | 说明 |
|---|--------|--------|------|------|
| 2.1 | catch 不吞异常 | P0 | ❌ | line 87 空 catch 块 |
| 4.3 | GROUP BY 去重 | P0 | ✅ | 已有 GROUP BY qtid |
| ... | ... | ... | ... | ... |

### <callee.m>（层 2）
| ... | ... | ... | ... | ... |

### 调用链
目标文件 → callee1.m → callee2.m
         → callee3.m

### 汇总
✅ 通过: N  ❌ P0: N  ⚠️ P1: N  💡 P2: N  N/A: N
```

**如果使用了 `--fix`，将 P0+P1 的失败项传入 `/fix` 流程处理。**
