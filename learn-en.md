---
description: 英文学习路径生成
argument-hint: [话题]
disable-model-invocation: true
---

针对给定话题，深度搜索并筛选最高质量的英文学习资料，输出分层学习路径。

## 参数

- **topic**：学习话题（缺少时询问）

## 默认假设

不问用户，直接按以下默认值开始搜索：
- **当前水平**：有概念
- **学习目的**：系统掌握
- **偏好形式**：都行

## 第一步：多轮搜索

**搜索策略：只找英文资料，质量 > 数量，宁缺毋滥。**

按优先级依次搜索以下来源：

| 优先级 | 来源类型 | 搜索关键词模式 | 获取方式 |
|--------|----------|---------------|---------|
| P0 | 官方文档/教程 | `<topic> official documentation/tutorial` | WebSearch → WebFetch |
| P1 | 经典书籍 | `best books to learn <topic> site:reddit.com OR site:news.ycombinator.com` | WebSearch |
| P2 | 顶级课程 | `best <topic> course MIT/Stanford/Coursera/edX` | WebSearch |
| P3 | 实战项目 | `<topic> project-based learning / hands-on tutorial` | WebSearch |
| P4 | GitHub 仓库 | `awesome <topic>`, 高 star 学习仓库 | `gh` 命令 |
| P5 | 社区推荐 | `<topic> learning roadmap / recommended resources` | WebSearch → WebFetch |
| P6 | 论文/深度文章 | `<topic> seminal paper / deep dive` | WebSearch |

- 每个来源类型最多搜 2-3 轮，找到高质量结果即停
- WebFetch 只对最有价值的 3-5 个页面使用
- GitHub 仓库用 `gh` 命令获取 star 数等实时数据，禁止编造
- 搜不到的类型标注"未找到优质资源"后跳过

## 第二步：质量评估

对每个找到的资料按以下维度打分（1-5），只保留总分 ≥ 12 的：

| 维度 | 评判标准 |
|------|---------|
| **权威性** | 作者背景、机构背书、社区口碑 |
| **时效性** | 最近更新时间、是否覆盖最新版本 |
| **系统性** | 是否有清晰的学习路径、由浅入深 |
| **实操性** | 是否有代码示例、练习、项目 |

## 第三步：输出报告

保存到 `docs/learn/<topic-slug>.md`（目录不存在则创建）。

```markdown
# <Topic> 英文学习资料精选

> 整理时间: YYYY-MM-DD
> 学习者水平: 有概念
> 学习目标: 系统掌握

## 一句话建议

用一句话告诉读者：从哪开始、怎么学最高效。

## 学习路线图

用简洁的文字描述推荐的学习顺序和阶段划分。

## 入门阶段 (Getting Started)

每个资料格式：
### 1. 资料名称
- **类型**：书籍 / 课程 / 教程 / 仓库
- **链接**：URL
- **作者/机构**：
- **推荐理由**：为什么选这个（2-3 句，用自己的话）
- **社区评价**：Reddit/HN 上的典型评价摘要
- **适合谁**：
- **预计投入**：大致学习量（如 "20 小时视频 + 练习"）

## 进阶阶段 (Intermediate)

同上格式。

## 深入阶段 (Advanced)

同上格式。

## 实战资源 (Hands-on)

项目式学习、练习平台、挑战赛等。

## 速查资源 (Quick Reference)

Cheat sheets、速查手册、常用工具。

## 社区与持续学习

值得关注的博客、播客、Newsletter、Discord/Slack 社区。

## 避坑指南

哪些"热门"资料其实不推荐？为什么？

## 参考来源
```

## 守护栏

- **只收录英文资料**，中文资料一律跳过
- 禁止编造 URL，搜不到标注"未找到"
- GitHub 数据用 `gh` 实时获取，禁止凭记忆编 star 数
- 每个资料必须有推荐理由，不是简单罗列链接
- 商业课程标注是否付费及大致价格
- 事实给来源，主观判断标注"个人建议"或"社区共识"
- 过时资料（>3 年未更新且领域变化大）标注警告
