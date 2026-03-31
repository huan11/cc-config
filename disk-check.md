---
description: Mac 磁盘占用分析与清理策略
disable-model-invocation: true
---

对本机 Mac 进行全面磁盘占用分析，定位空间消耗大户，并给出可执行的清理策略。

## 分析流程

### 第一步：磁盘总览

```bash
# 磁盘总量与使用率
df -h /
# APFS 卷详情
diskutil apfs list 2>/dev/null | head -40
```

输出磁盘总量、已用、可用、使用百分比。使用率 > 80% 标记告警。

### 第二步：系统级大户分析

逐项执行以下命令，统计各类目录占用空间：

```bash
# 用户主目录各子目录占用（Top 15）
du -sh ~/*/  2>/dev/null | sort -rh | head -15
du -sh ~/.*/ 2>/dev/null | sort -rh | head -10

# 关键系统目录
du -sh ~/Library/Caches 2>/dev/null
du -sh ~/Library/Logs 2>/dev/null
du -sh ~/Library/Application\ Support 2>/dev/null
du -sh ~/Library/Developer 2>/dev/null
du -sh ~/Library/Containers 2>/dev/null
du -sh ~/Library/Group\ Containers 2>/dev/null
du -sh ~/Library/Mail 2>/dev/null
du -sh /Library/Caches 2>/dev/null
du -sh /System/Volumes/Data/.Spotlight-V100 2>/dev/null
du -sh /private/var/folders 2>/dev/null
```

### 第三步：开发工具占用

```bash
# Homebrew
du -sh /opt/homebrew 2>/dev/null || du -sh /usr/local/Homebrew 2>/dev/null
brew cleanup --dry-run 2>/dev/null | tail -5

# Node.js / npm / pnpm / bun
du -sh ~/.npm 2>/dev/null
du -sh ~/Library/pnpm 2>/dev/null
du -sh ~/.bun 2>/dev/null
du -sh ~/.nvm 2>/dev/null
find ~ -maxdepth 4 -name "node_modules" -type d 2>/dev/null | head -20 | xargs -I{} du -sh {} 2>/dev/null | sort -rh

# Python / uv / pip
du -sh ~/.local/share/uv 2>/dev/null
du -sh ~/Library/Caches/uv 2>/dev/null
du -sh ~/.cache/pip 2>/dev/null
du -sh ~/.local/lib 2>/dev/null
find ~ -maxdepth 4 -name ".venv" -type d 2>/dev/null | head -20 | xargs -I{} du -sh {} 2>/dev/null | sort -rh

# Java / Maven
du -sh ~/.m2 2>/dev/null
du -sh ~/.gradle 2>/dev/null

# Rust
du -sh ~/.cargo 2>/dev/null
du -sh ~/.rustup 2>/dev/null

# Go
du -sh ~/go 2>/dev/null

# Xcode
du -sh ~/Library/Developer/Xcode 2>/dev/null
du -sh ~/Library/Developer/CoreSimulator 2>/dev/null
```

### 第四步：Docker 占用

```bash
docker system df 2>/dev/null
docker system df -v 2>/dev/null | head -40
# Docker Desktop VM 磁盘文件
du -sh ~/Library/Containers/com.docker.docker 2>/dev/null
```

### 第五步：大文件猎手

```bash
# 用户目录下 > 500MB 的文件
find ~ -type f -size +500M 2>/dev/null | head -20 | xargs -I{} ls -lh {} 2>/dev/null

# 用户目录下 > 100MB 的文件（Top 30）
find ~ -type f -size +100M 2>/dev/null | head -50 | xargs -I{} du -h {} 2>/dev/null | sort -rh | head -30
```

### 第六步：回收站与临时文件

```bash
du -sh ~/.Trash 2>/dev/null
du -sh /tmp 2>/dev/null
du -sh /private/var/tmp 2>/dev/null
du -sh ~/Downloads 2>/dev/null
```

### 第七步：Claude Code 会话文件

```bash
du -sh ~/.claude 2>/dev/null
du -sh ~/.claude/projects 2>/dev/null
find ~/.claude/projects -name "*.jsonl" 2>/dev/null | wc -l
find ~/.claude/projects -name "*.jsonl" -size +10M 2>/dev/null | head -10 | xargs -I{} ls -lh {} 2>/dev/null
```

## 输出格式

### 一、磁盘总览

| 项目 | 值 |
|------|-----|
| 总容量 | xxx GB |
| 已用 | xxx GB (xx%) |
| 可用 | xxx GB |

### 二、空间占用排行榜

按占用从大到小排列，标注占总已用空间的百分比：

| 排名 | 目录/类别 | 占用 | 占比 | 说明 |
|------|-----------|------|------|------|
| 1 | ~/Library/Developer | 45G | 18% | Xcode 相关 |
| 2 | ~/docker | 30G | 12% | Docker 数据 |

### 三、开发工具占用明细

| 工具 | 缓存/数据路径 | 占用 | 可清理 |
|------|--------------|------|--------|
| Homebrew | /opt/homebrew | 5G | 部分 |
| uv | ~/.local/share/uv | 3G | 部分 |
| node_modules（散落） | 多处 | 8G | 大部分 |

### 四、大文件 Top 10

| 文件路径 | 大小 | 类型 | 建议 |
|---------|------|------|------|
| ~/xxx.dmg | 4G | 安装包 | 删除 |

### 五、清理策略

按风险等级分三档，每档按预计释放空间从大到小排序：

**安全清理（无风险，直接执行）：**

| 序号 | 操作 | 命令 | 预计释放 |
|------|------|------|---------|
| 1 | 清空回收站 | `rm -rf ~/.Trash/*` | xG |
| 2 | 清理 Homebrew 缓存 | `brew cleanup --prune=all` | xG |
| 3 | 清理 pip/uv 缓存 | `uv cache clean` | xG |
| 4 | 清理 npm 缓存 | `npm cache clean --force` | xG |
| 5 | 清理系统日志 | `sudo rm -rf ~/Library/Logs/*` | xG |
| 6 | 清理系统缓存 | `rm -rf ~/Library/Caches/*` | xG |

**谨慎清理（低风险，建议确认后执行）：**

| 序号 | 操作 | 命令 | 预计释放 | 注意事项 |
|------|------|------|---------|---------|
| 1 | 清理不活跃项目的 node_modules | 手动逐个 | xG | 可用 npm install 恢复 |
| 2 | 清理不活跃项目的 .venv | 手动逐个 | xG | 可用 uv sync 恢复 |
| 3 | Docker 清理未用镜像 | `docker system prune -a` | xG | 会删除所有未运行容器的镜像 |
| 4 | 清理旧的 Claude Code 会话 | 手动删除大文件 | xG | 历史记录不可恢复 |

**深度清理（需评估，可能影响工作流）：**

| 序号 | 操作 | 命令 | 预计释放 | 风险 |
|------|------|------|---------|------|
| 1 | 删除 Xcode 模拟器 | `xcrun simctl delete unavailable` | xG | 需要时重新下载 |
| 2 | 清理 Maven 本地仓库 | `rm -rf ~/.m2/repository` | xG | 下次构建重新下载 |

### 六、总结

- 当前磁盘健康度：健康 / 偏紧 / 告急
- 预计可释放总空间：xx GB
- 最大收益操作 Top 3

## 守护栏

- 分析阶段只读，不执行任何删除或修改命令
- 清理策略只输出命令建议，不自动执行
- 用户明确要求执行某项清理时，逐项确认后再执行
- `find` 命令加 `head` 限制输出量，防止扫描时间过长
- 遇到权限不足的目录跳过，不使用 sudo（除非用户要求）
- 不扫描外接磁盘和网络挂载卷
