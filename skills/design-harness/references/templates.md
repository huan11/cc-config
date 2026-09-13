# 文件骨架(逐段对应 SKILL.md 的六段)

> 都是骨架不是范文。目录怎么切不唯一,关键是**在 AGENTS.md 里说明谁读谁写**。

## 一、目录骨架

```bash
git init
mkdir -p docs/decisions skills scripts/cron plans state
ln -s AGENTS.md CLAUDE.md      # 让 Claude Code 也读到同一份入口
```

`.gitignore` 起手(凭据策略见四段,要跟用户确认):

```gitignore
__pycache__/
*.pyc
.venv/
*.log
scripts/cron/logs/
.DS_Store
# 若凭据不入库,在此加上具体文件名
```

---

## 二、AGENTS.md(入口层,50–200 行)

```markdown
# <项目名 / 岗位名>

## 角色定位
你是 <角色>,负责 <职责范围>。
**你不做**:<哪些决策必须回来问人——花钱、对外发布、删数据、动生产、改权限>
**汇报方式**:<产出放哪、怎么通知人>

## 目标管理
**北极星**:<一句话,可衡量>
| 子目标 | 验收指标 | 当前值 |
|---|---|---|
| <子目标> | <可用是/否判定的量化条件> | 见 state/STATUS.md |

## 任务清单
| 任务 | 输入 | 输出 | 用哪个技能 | 状态 |
|---|---|---|---|---|
| <任务> | <从哪来> | <写到哪> | skills/<name> | 见 state/TODO.md |

## 项目结构
<目录树,每行注释"谁读谁写">
新机器首次使用:`bash setup.sh`

## 原则与优先级
核心原则在 docs/constitution.md,开始任何工作前先读。
模块级权衡在 docs/decisions/,处理该模块前先读对应 ADR。
业务词汇见 docs/glossary.md。外部环境接入见 docs/environment.md。
**冲突时按此裁决**:
1. 红线(constitution.md 标注为红线的)  2. 用户当面的指令
3. 项目级规则  4. 模块级 ADR  5. 最佳实践

## 可用技能
| 技能 | 加载名 | 做什么 | 读哪里的计划 | 进度写哪里 |
|---|---|---|---|---|
| <中文名> | <name> | <一句话> | plans/<x>/ | state/<x>/ |
详细用法在各自 SKILL.md。**必须先加载技能再执行**。

## 计划与调整(外层循环)
- 计划参数存放:state/<x>/plan.json
- 检查节奏:<每周/每月,看哪个指标>
- 指标 >X% → <动作>;指标 <Y% → <动作>
- **计划调整只在这里做,技能不负责调整计划**

## 边界情况
- 如果 <条件> → <动作>
- 如果 <条件> → <动作>

## 什么时候算完成
<可用是/否判定的量化条件>

## 完成检查(职责边界)
每次会话结束后:
1. 更新 state/ 下的 progress.json,**只记原始数据**(做了多少、跳过哪些及原因、指标当前值)
2. 运行 `python scripts/check_progress.py`
3. 只有输出 PASS 才算完成;FAIL 时按脚本指出的指标继续做
4. **禁止自行宣布完成**,以脚本输出为准

## 会话开场检查
1. 读 state/STATUS.md 和 state/TODO.md,明确现在在哪、下一步做什么
2. 询问用户:「<外部信息源> 是否有更新?」有 → 更新对应文件与计划并告知;无 → 继续
```

---

## 三、业务知识

### docs/constitution.md

```markdown
# <项目名> - 原则文档

## 红线(不可协商)
### 1. <规则一句话>
Rationale: <为什么>。即使"赶时间上线"也要遵守。

## 规则(通常遵守)
### 2. <规则一句话>
Rationale: <为什么>。用户明确要求时可以覆盖。

## 建议(灵活处理)
### 3. <规则一句话>

## 治理
<谁能改、怎么改> | 版本:<版本> | 批准日期:<日期>
```

### docs/decisions/adr-NNN-<主题>.md

```markdown
# ADR-001:<决策一句话>
## 上下文
<面对什么问题,有哪些可选路径>
## 决策
<最终选了什么>
## 权衡
选择了"<X>优先"而非"<Y>优先"。代价是 <代价>。
## 影响
<对其他模块 / 后续新模块的约束>
```

### docs/SOURCE.md

```markdown
## 外部知识依赖
本仓库中以下内容来自仓库之外,必须按期同步:

| 仓库文件 | 外部来源 | 更新时机 | 同步方式 |
|---|---|---|---|
| docs/api-spec.md | 飞书文档 (https://…) | 每周一 | skills/sync-sources |
| docs/需求台账.md | 飞书多维表格 (https://…) | 按需 | 会话开场询问 |
| docs/architecture.md | ADR 仓库 (https://…) | 每次 PR 合并 | scripts/cron |
```

`sync-sources` 技能的下单话术:

> 请根据 docs/SOURCE.md 的映射,创建 sync-sources 技能:1) 读 SOURCE.md 取全部映射;
> 2) 对每个来源通过 URL/API 拉最新内容;3) 与本地文件比对,有差异则更新;
> 4) 更新后提 PR,注明改了哪些文件和内容摘要;5) 标"按需"的每次运行询问用户;
> 6) 支持手动触发与 cron。生成 SKILL.md,含描述、触发条件、执行步骤、工具声明。

### docs/rules.md(规则登记表,轻量场景可替代 ADR)

```
编号: R001
内容: <规则一句话>
来源: <为什么加这条>
优先级: 红线 / 规则 / 建议
适用条件: <什么时候需要它>
过期条件: <什么情况下可以删>      ← 没有它,这条规则永远删不掉
状态: active / superseded / deprecated
----
```

配套 `rule-conflict-audit` 技能(定期跑,或会话开场跑):

```markdown
---
name: rule-conflict-audit
description: 定期检查规则登记表,找出互相矛盾的规则对并给出裁决建议。登记表变更时、例行维护时使用。
---
# rule-conflict-audit —— 规则矛盾检测
读取 docs/rules.md,找出矛盾规则对,按优先级给裁决建议,输出冲突报告。

**Guides**:取全部条目(编号、内容、来源、优先级、适用条件、过期条件、状态)。
**Action**:逐对检查**适用条件是否重叠**(只有重叠才可能矛盾);对重叠的判断行为是否互斥、
是否指向相反结果、是否可能同时触发。
**Sensors**:每个矛盾对输出:涉及规则及优先级、冲突点、裁决建议(高优先级胜出;
同级时更接近当前现实的胜出;无法裁决标「待人工」)、触发场景。
**Steering**:生成报告。「待人工」的列给用户决定保留/修改/删除;确认后更新状态;
删除留痕,标 deprecated 而非直接消失。
```

---

## 四、docs/environment.md(环境接入清单)

```markdown
# 环境接入清单

## 机器
| 代号 | 怎么连 | 干什么 | 权限边界 | 凭据在哪 |
|---|---|---|---|---|
| <L207> | `ssh root@…` | 生产部署、看日志 | 只碰 /opt/app | <路径 or 入库位置> |

## 数据库
| 实例 | 怎么连 | 可读/可写的库 | 禁止 | 凭据在哪 |
|---|---|---|---|---|
| <RDS01> | `mysql -h … -u ro_user` | db_a(读) / db_b(读写) | 不许 DROP / TRUNCATE | <位置> |

## 第三方平台
| 平台 | 接入方式 | 干什么 | 权限边界 |
|---|---|---|---|
| 飞书多维表格 | MCP `<name>` | 读需求台账、回填状态 | 只碰 <某个 base> |
| GitHub | CLI `gh` | 建仓库、提 PR | 只限 org `<org>` |

## 浏览器 / 屏幕
| 场景 | 方式 | 什么时候才用 |
|---|---|---|
| 需登录态的页面 | 浏览器自动化 MCP | 无 API 可用时 |
| 看 GUI 渲染效果 | 截图 MCP | CLI 拿不到时 |

## 接入方式选择原则
CLI > MCP > 浏览器自动化 > 屏幕控制。越往后越慢越飘,每次升级都要说得出理由。

## 可复现
依赖锁在 requirements.txt;`bash setup.sh` 做到 clone 后一条命令可用。
Agent 无端变差时**先查本节**,再怀疑提示词和模型。
```

### setup.sh / requirements.txt

```bash
#!/usr/bin/env bash
set -euo pipefail
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# 其余:建目录、初始化 state/、检查外部命令是否就位(ssh/gh/mysql)
```

> 描述工具代码时顺带一句"同时生成 requirements.txt 和 setup.sh",Agent 会分析用到的三方库自动生成。

---

## 五、技能与工具

### skills/<name>/SKILL.md

```
my-skill/
├── SKILL.md      # 必需:元数据 + 操控循环
├── scripts/      # 可选:工具代码
├── references/   # 可选:参考资料
└── assets/       # 可选:模板
```

```markdown
---
name: <唯一标识,AGENTS.md 按这个名字引用>
description: <写触发条件,不写介绍——它决定会不会被自动加载>
allowed-tools:
  - <可选,如 scripts/xxx.py>
---

# <name> —— <中文名>
从 `plans/<x>/…` 读取本轮计划,从 `state/<x>/` 读写进度。
<本技能的特点、与常规做法的关键区别>

**Guides**:<动手前读什么、什么条件才开工;只说用途,让 Agent 自己推断调哪个函数>
**Action**:<具体做什么、怎么交互>
**Sensors**:<拿什么标准判定,分几档>
**Steering**:<不达标怎么办;状态怎么写回>

> 本技能仅负责执行,不负责任何计划调整决策。
> 评分标准 / 调整规则 / 完成判定 → 见 AGENTS.md。
```

工具代码开头写清函数清单,Agent 靠它推断调用:

```python
#!/usr/bin/env python3
"""<工具用途>。<哪些技能共用>。
工具函数(由 SKILL.md 中的操控循环调用):
  get_due_items(progress)      — 今天到期的条目
  update_item(progress, id, r) — 记录结果后更新状态
  get_stats(progress)          — 完成率、异常率
"""
```

不会写代码时的下单话术:

> 我在构建一个 <X> 的 Agent 系统。需要一个 Python 工具,作用是 <要判断/计算什么>。
> 输入是 <数据及字段>,如果 <条件> 就 <输出>。请实现它,
> **并为要调用它的 Skill 生成使用说明**,同时生成 requirements.txt 和 setup.sh。

### scripts/check_progress.py(验证器,下单话术)

> 请编写 scripts/check_progress.py:1) 读取 <全部 progress.json 路径>;
> 2) 逐项检查 <指标 A 字段> 是否达到 <阈值>、<指标 B 字段> 是否为 <目标值>;
> 3) 全部达标输出 **PASS** 并列出各项数值;有未达标输出 **FAIL**,明确指出哪一项、
> 哪个指标、当前值多少;4) **只依赖标准库,只用 progress.json 中的数值字段判断,
> 不读取也不解析任何对话内容或 LLM 生成的主观描述**;5) 任何一项不达标都输出 FAIL。

### scripts/cron/(定时任务登记)

`scripts/cron/README.md`:

```markdown
| 任务 | 频率 | 命令 | 日志 | 失败怎么通知 | 跑在哪台机器 |
|---|---|---|---|---|---|
| 同步外部知识 | 每周一 09:07 | `python scripts/sync_sources.py` | logs/sync.log | 飞书机器人 | <机器> |
| 接口健康检查 | 每 10 分钟 | `python scripts/api_health.py` | logs/api.log | 飞书机器人 | <机器> |
| 规则矛盾检测 | 每周日 | `claude -p "/rule-conflict-audit"` | logs/audit.log | 仅报告 | <机器> |
```

`scripts/cron/crontab.txt`(入库,别只存在某台机器的 crontab 里):

```cron
# 避开整点:整点是全网最堵的时刻
7 9 * * 1  cd /path/to/harness && .venv/bin/python scripts/sync_sources.py >> scripts/cron/logs/sync.log 2>&1
```

---

## 六、状态

### state/STATUS.md(水位线,给人看)

```markdown
# 当前状态
> 最后更新:<日期>(每次会话结束更新)

## 现在处于什么水平
<一段话:这套 harness 现在能稳定做什么、还不能做什么>

## 已具备的能力
- [x] <能力> — 证据:<脚本/技能/文档>

## 正在做
<当前任务 + 卡在哪>

## 下一个里程碑
<目标 + 验收指标 + 预计节奏>
```

### state/TODO.md(台账,给人和 Agent 看)

```markdown
| ID | 任务 | 状态 | 依赖 | 卡在哪 / 下一步 |
|---|---|---|---|---|
| T001 | <任务> | 待办 / 进行中 / 阻塞 / 完成 | T000 | <具体的下一动作> |
```

### state/<task>/progress.json(给机器看,只记原始数据)

```json
{
  "updated_at": "<日期>",
  "plan_ref": "plans/<x>/week-01.md",
  "items": {
    "<id>": { "status": "done|skipped|pending", "skip_reason": "<为什么跳>", "result": {} }
  },
  "stats": { "total": 100, "processed": 30, "skipped": 70, "pass_rate": 0.42 }
}
```

> 只写"已处理 30 条,跳过 70 条""正确率 0.42";不写"处理得很好""基本达标"。
> 验证器不需要解读,只需对照条件打勾。

### plans/(外层下发,按需)

```json
{ "current_round": 2, "phase": "learning|review", "quota": 10, "focus": "<本轮重点>" }
```

闭环:`plans/` 下发 → 技能执行 → `state/` 回报 → AGENTS.md 的调整规则决定下一轮 `plans/`。
