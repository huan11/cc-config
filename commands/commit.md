---
description: 按 Angular 规范提交代码
disable-model-invocation: true
---

按 Angular Commit 规范提交代码，提交前必须确保文档同步更新。

## 当前状态

!`git status`

!`git diff --stat`

!`git log --oneline -5`

## 提交流程

### 第一步：检查变更

基于上方自动注入的 git 状态，梳理所有变更文件，按类别分组：

| 类别 | 文件 |
|------|------|
| 新增 | ... |
| 修改 | ... |
| 删除 | ... |

### 第二步：文档同步检查

逐项检查以下文档是否需要同步更新：

- [ ] **README.md** — 项目结构、能力说明是否和代码一致
- [ ] **CLAUDE.md** — 规则是否需要新增或调整
- [ ] **docs/** 下的文档 — 是否有新规则、新命令、新 skill 未记录

如果有文档需要更新，**先更新文档，再进入提交步骤**。
如果文档已同步，标注"文档已同步，无需更新"。

### 第三步：生成 commit message

严格使用 Angular Commit 规范：

```
<type>(<scope>): <subject>

<body>
```

**type 必须是以下之一：**

| type | 用途 |
|------|------|
| feat | 新功能 |
| fix | 修复 bug |
| docs | 仅文档变更 |
| style | 格式调整（不影响逻辑） |
| refactor | 重构（不是新功能也不是修复） |
| perf | 性能优化 |
| test | 测试相关 |
| build | 构建/依赖变更 |
| ci | CI/CD 配置变更 |
| chore | 其他杂项 |

**规则：**
- scope 用中文，简明标注影响范围
- subject 用中文，不超过 50 字
- 如果本次变更涉及多个 type，拆成多次提交
- body 可选，复杂变更时补充说明

### 第四步：确认并提交

把生成的 commit message 展示给用户，询问：

**确认提交？（0=不提交需要调整 / 1=确认提交）**

- 用户回复 1 → 执行提交
- 用户回复 0 → 询问需要调整什么

```bash
git add <具体文件>
git commit -m "<message>"
```

**禁止 `git add .` 或 `git add -A`，必须逐个添加文件。**
