---
description: 远程 Linux 服务器全面巡检（服务、端口、资源、Docker）
disable-model-invocation: true
---

对远程 Linux 服务器进行全面巡检，输出当前运行状态的完整快照。

## 连接信息

- 如果用户指定了 SSH 连接命令，使用该命令
- 如果未指定，从 CLAUDE.md 中查找远程 Linux 机器的连接信息
- 连接失败 → 立即终止并报错，不猜测

## 巡检项（所有命令通过 SSH 远程执行）

### 1. 系统概览

```bash
hostname && uname -a
cat /etc/os-release | head -5
uptime
who
```

输出：主机名、内核版本、OS 发行版、运行时长、当前登录用户

### 2. 资源使用

```bash
# CPU
nproc && lscpu | grep "Model name"
# 内存
free -h
# 磁盘
df -h | grep -v tmpfs | grep -v loop
# inode
df -i | grep -v tmpfs | grep -v loop
```

标记告警：内存可用 < 20%、磁盘使用 > 80%、inode 使用 > 80%

### 3. 端口监听

```bash
ss -tlnp
ss -ulnp
```

输出所有 TCP/UDP 监听端口，包含进程名和 PID。按端口号排序整理成表格。

### 4. Docker 服务

```bash
docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
docker compose ls
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
docker system df
```

- 列出所有容器（含已停止的）
- 列出所有 compose 项目
- 列出容器资源占用
- 列出 Docker 磁盘占用
- 标记非 running 状态的容器

### 5. Systemd 服务

```bash
systemctl list-units --type=service --state=running --no-pager
systemctl list-units --type=service --state=failed --no-pager
```

- 列出所有运行中的服务
- 特别标记 failed 状态的服务

### 6. 后台进程

```bash
# 占用资源最多的 Top 15 进程
ps aux --sort=-%mem | head -16
# 常驻守护进程
ps -eo pid,ppid,user,%cpu,%mem,etime,comm --sort=-%mem | head -20
```

### 7. 定时任务

```bash
crontab -l 2>/dev/null || echo "无用户级 crontab"
ls /etc/cron.d/ 2>/dev/null
systemctl list-timers --no-pager 2>/dev/null
```

### 8. 网络与安全

```bash
# 公网 IP
curl -s --connect-timeout 3 ifconfig.me || echo "无法获取公网IP"
# 防火墙
ufw status 2>/dev/null || iptables -L -n --line-numbers 2>/dev/null | head -30 || echo "无防火墙工具"
# 最近登录
last -n 10 --time-format short
# SSH 失败尝试（最近 20 条）
journalctl -u sshd --no-pager -n 20 --grep="Failed" 2>/dev/null || grep "Failed" /var/log/auth.log 2>/dev/null | tail -10 || echo "无法读取 SSH 日志"
```

### 9. 软件版本

```bash
docker --version 2>/dev/null
docker compose version 2>/dev/null
python3 --version 2>/dev/null
node --version 2>/dev/null
java -version 2>&1 | head -1 || true
git --version 2>/dev/null
nginx -v 2>&1 || true
```

仅列出已安装的工具，忽略不存在的。

### 10. Nginx 反向代理映射

仅在检测到 Nginx 已安装且运行时执行此项，否则跳过。

```bash
# 检查 Nginx 是否运行
systemctl is-active nginx 2>/dev/null || echo "nginx_not_running"
# 提取所有 Nginx 配置中的 proxy_pass 映射
nginx -T 2>/dev/null | grep -E '(server_name|location|proxy_pass)' | sed 's/^[[:space:]]*//'
```

- 解析 Nginx 配置，提取所有 `location + proxy_pass` 组合
- 将 proxy_pass 的目标端口与 Docker 容器端口、Systemd 服务端口进行交叉比对，标注对应的后端服务名
- 如果某个 proxy_pass 目标端口没有任何进程监听，标记为告警

## 输出格式

### 一、系统概览

| 项目 | 值 |
|------|-----|
| 主机名 | xxx |
| OS | Ubuntu 20.04 |
| 内核 | 5.4.0-xxx |
| 运行时长 | xx days |
| CPU | x 核 / 型号 |
| 内存 | 已用/总量 (百分比) |
| 磁盘 | 已用/总量 (百分比) |
| 公网 IP | x.x.x.x |

### 二、端口占用

| 协议 | 端口 | 地址 | 进程 | 备注 |
|------|------|------|------|------|
| TCP | 22 | 0.0.0.0 | sshd | - |
| TCP | 5432 | 0.0.0.0 | docker-proxy | PostgreSQL |

对常见端口自动标注用途（22=SSH, 80/443=HTTP/S, 3306=MySQL, 5432=PG, 6379=Redis, 8080=HTTP, 27017=MongoDB 等）

### 三、Docker 服务

| 容器名 | 镜像 | 状态 | 端口映射 | CPU | 内存 |
|--------|------|------|---------|-----|------|

Compose 项目：

| 项目名 | 状态 | 配置文件路径 |
|--------|------|-------------|

Docker 磁盘占用汇总。

### 四、系统服务

**运行中（关键服务）：**

| 服务 | 状态 | 说明 |
|------|------|------|

**失败的服务：**（如有）

| 服务 | 状态 | 需要关注 |
|------|------|---------|

### 五、资源 Top 进程

| PID | 用户 | CPU% | 内存% | 运行时长 | 命令 |
|-----|------|------|-------|---------|------|

### 六、定时任务

列出所有 crontab 条目和 systemd timer。

### 七、安全概览

- 防火墙状态
- 最近登录记录
- SSH 失败尝试（如有异常数量标注告警）

### 八、已安装工具版本

| 工具 | 版本 |
|------|------|

### 九、Nginx 反向代理映射

（仅在 Nginx 运行时输出，否则显示"未检测到 Nginx"并跳过）

**域名：** example.com

| URL 路径 | 后端地址 | 路径改写 | 对应服务 | 备注 |
|----------|---------|---------|---------|------|
| /api/ | http://127.0.0.1:8012 | 去掉 /api 前缀 | java (klcjfof-admin) | Spring Boot |
| /fund-api/ | http://127.0.0.1:8080/ | 去掉 /fund-api 前缀 | fund-service (Docker) | 基金助手 |

- "对应服务"列通过端口号交叉比对 Docker 容器端口映射和 `ss -tlnp` 的进程信息自动填充
- "路径改写"列标注 rewrite 规则或 proxy_pass 末尾 `/` 导致的路径剥离
- 如果 proxy_pass 目标端口无进程监听，在备注标注"端口无监听"

### 十、告警汇总

将所有异常集中展示：

| 级别 | 项目 | 详情 | 建议 |
|------|------|------|------|
| P0 | 磁盘使用 92% | /dev/sda1 | 清理日志或扩容 |
| P1 | 容器 xxx 已停止 | Exited (1) 3 days ago | 检查日志 |
| P2 | 3 次 SSH 失败登录 | 来自 x.x.x.x | 考虑 fail2ban |

无异常 → 输出"所有检查项正常"。

## 守护栏

- 所有操作只读，禁止执行任何修改命令
- 禁止输出密码、密钥、Token 等敏感信息
- SSH 命令设置超时（单条命令 10 秒），防止卡死
- 每个巡检项独立执行，某项失败不影响其他项
- 如果某些命令需要 sudo 权限但当前用户无权限，标注"权限不足"跳过，不报错终止
