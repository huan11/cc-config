# Skills 清单

> 人看的技能索引。每个 skill = `~/.claude/skills/<名>/SKILL.md`，由 Claude 按 `description` **自动触发**，也可 `/名` 手动调用。
> 新增/更新 skill 后在此加一行。最后更新：2026-09-13。
>
> ⚠️ **工具空间正在重整中**（2026-09-13 全清重建）。现存 1 个 skill，其余全部已归档进 git 历史，见文末。

| Skill | 用途 | 何时触发 |
|-------|------|---------|
| **design-harness** | **把用户手上的散料转成一个能跑的标准 Harness 仓库**：先一次性收料(8 项)+ 出缺口清单，再按六段落地——目录骨架 / 指令系统(角色+目标+任务+验收)/ 业务知识(constitution+SOURCE)/ 环境接入(cli-mcp-浏览器)/ 技能与脚本(含验证器+定时任务)/ 状态台账(STATUS+TODO+progress)。方法论(双层循环、四子系统、5 坏味道)藏在 references/ 当作业依据 | "帮我给这摊活搭套 harness / Agent 系统"；"这是我手上的资料，整成 Agent 能用的仓库"；"AGENTS.md 怎么写"；或既有 harness"时好时坏、说做完其实没做完、规则越加越笨" |

## 约定

- **一个能力域一个 skill**（不按单个操作拆分）。
- **`description` 写触发条件、不写介绍**——它决定会不会被自动加载。
- **沉淀触发器**：每摸通一个磨人的流程，当场沉淀/更新成 skill，不留到下次重来。
- 非技能目录（无 SKILL.md）不计入本清单。
- **凭据不入库**：真值放 `~/.config/*.env`（600），skill 里只写变量名与文件路径。

## 已归档（2026-09-13 全清）

重整前的完整工具空间在 commit **`13166ee`** 里：**110 个斜杠命令 + 6 个 skill**。
盘点报告见仓库根 [`工具空间盘点-2026-09-13.md`](../工具空间盘点-2026-09-13.md)（含按能力域归档、7 组重复、12 个绑死环境的命令、重整建议）。

被清掉的 5 个 skill：`big-screen`、`excalidraw-diagram`、`feishu-bitable`、`kimi-webbridge`、`opc`（+ `opc-workspace`）。

**取回单个文件**：

```bash
cd ~/.claude
git checkout 13166ee -- commands/make-repo-card.md        # 取回一个命令
git checkout 13166ee -- skills/feishu-bitable             # 取回一个 skill
git show 13166ee --stat | head -40                        # 看归档里都有什么
```

另有离线 zip 备份（含 commands 的完整 git 历史）：`~/Documents/cc-commands-2026-09-13.zip`、`~/Documents/cc-skills-2026-09-13.zip`。
