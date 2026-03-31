---
description: GitHub 创建远程仓库并推送
disable-model-invocation: true
---

在 GitHub 上创建远程仓库并推送当前项目。

## 执行流程

### 第一步：环境检查

1. 运行 `gh auth status` 确认 GitHub CLI 已登录
2. 运行 `git remote -v` 检查是否已有远程仓库
   - 如果已有 origin，提示用户并询问是否要替换
3. 确认当前目录是 git 仓库，且有至少一次提交

如果 gh 未登录，提示用户先运行 `gh auth login`。

### 第二步：选择组织

1. 运行 `gh api user/orgs --jq '.[].login'` 获取用户所属的组织列表
2. 展示选项供用户选择：
   - 个人账号（默认）
   - 各个组织

询问用户要创建到哪个账号/组织下。

### 第三步：确认仓库信息

收集并展示以下信息，让用户确认：

| 项目 | 值 |
|------|-----|
| 仓库名 | 当前目录名（或用户指定） |
| 所属 | 个人 / 组织名 |
| 可见性 | private（默认） / public |
| 分支 | 当前分支名 |

**确认创建？（0=调整 / 1=确认）**

### 第四步：创建并推送

```bash
# 如果已有 origin 需要替换
git remote remove origin

# 创建仓库并推送（组织下）
gh repo create <org>/<repo-name> --private --source=. --push

# 或个人账号下
gh repo create <repo-name> --private --source=. --push
```

创建完成后展示仓库 URL。

### 注意事项

- 默认创建 **private** 仓库，除非用户明确要求 public
- 仓库名默认使用当前目录名，用户可自定义
- 如果已有同名仓库，gh 会报错，提示用户处理
