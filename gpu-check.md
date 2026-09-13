---
description: 检查 GPU 机器的硬件配置、驱动、显存、利用率和运行中的 GPU 进程
---

检查 GPU 机器的完整配置信息，输出硬件规格、驱动版本、显存占用、GPU 利用率和运行中的进程。

## 连接信息

- 如果用户指定了 SSH 连接命令或机器代码（如 D01），使用对应连接
- 如果未指定，默认连接 D01：`ssh -p 42412 admin@lanyang.ddns.net`
- 连接失败 → 立即终止并报错

## 检查项（所有命令通过 SSH 远程执行）

### 1. 系统与驱动概览

```bash
hostname && uname -r
cat /etc/os-release | head -3
uptime
```

### 2. GPU 硬件与驱动

```bash
nvidia-smi
```

从 nvidia-smi 输出中提取：驱动版本、CUDA 版本、GPU 型号、GPU 数量。

### 3. GPU 详细规格

```bash
nvidia-smi -q | grep -E "(Product Name|GPU UUID|Total|Used|Free|Temperature|Power Draw|Power Limit|Performance State|Compute Mode)"
```

### 4. GPU 拓扑（多卡时）

```bash
nvidia-smi topo -m 2>/dev/null || echo "单卡或不支持拓扑查询"
```

### 5. CUDA 工具链

```bash
nvcc --version 2>/dev/null || echo "nvcc 未安装"
cat /usr/local/cuda/version.txt 2>/dev/null || ls /usr/local/cuda*/version.txt 2>/dev/null || echo "无 CUDA toolkit 版本文件"
```

### 6. GPU 进程

```bash
nvidia-smi pmon -c 1 2>/dev/null || nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || echo "无 GPU 进程"
```

### 7. CPU / 内存 / 磁盘概览（GPU 机器的宿主资源）

```bash
nproc && lscpu | grep "Model name"
free -h
df -h | grep -v tmpfs | grep -v loop
```

### 8. Docker GPU 支持

```bash
# 检查 nvidia-container-toolkit
dpkg -l 2>/dev/null | grep nvidia-container || rpm -qa 2>/dev/null | grep nvidia-container || echo "未安装 nvidia-container-toolkit"
# 检查 Docker nvidia runtime
docker info 2>/dev/null | grep -i nvidia || echo "Docker 无 nvidia runtime"
# GPU 容器
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null | head -20
```

### 9. 深度学习环境

```bash
python3 -c "import torch; print(f'PyTorch {torch.__version__}, CUDA available: {torch.cuda.is_available()}, Devices: {torch.cuda.device_count()}')" 2>/dev/null || echo "无 PyTorch"
python3 -c "import tensorflow as tf; print(f'TensorFlow {tf.__version__}, GPUs: {len(tf.config.list_physical_devices(\"GPU\"))}')" 2>/dev/null || echo "无 TensorFlow"
conda info --envs 2>/dev/null || echo "无 Conda"
```

## 输出格式

### 一、系统概览

| 项目 | 值 |
|------|-----|
| 主机名 | xxx |
| 内核 | 6.x.x |
| OS | Ubuntu xx.xx |
| 运行时长 | xx days |
| CPU | x 核 / 型号 |
| 内存 | 已用/总量 |

### 二、GPU 配置

| # | 型号 | 显存 | 驱动 | CUDA | 状态 |
|---|------|------|------|------|------|
| 0 | A100 80GB | 已用/总量 | 535.xx | 12.x | P0/Idle |

### 三、GPU 实时状态

| # | 温度 | 功耗 | 功耗上限 | GPU利用率 | 显存利用率 |
|---|------|------|---------|----------|-----------|
| 0 | 45°C | 60W | 300W | 0% | 5% |

### 四、GPU 进程

| PID | 进程 | GPU# | 显存占用 |
|-----|------|------|---------|

无进程 → 显示"当前无 GPU 进程"。

### 五、GPU 拓扑（多卡时）

展示 nvidia-smi topo 的互联矩阵（NVLink / PCIe）。单卡则跳过。

### 六、Docker GPU 支持

| 项目 | 状态 |
|------|------|
| nvidia-container-toolkit | 已安装/未安装 |
| Docker nvidia runtime | 可用/不可用 |

GPU 容器列表（如有）。

### 七、深度学习环境

| 框架 | 版本 | GPU 可用 | 可用设备数 |
|------|------|---------|-----------|

### 八、磁盘概览

| 挂载点 | 大小 | 已用 | 可用 | 使用率 |
|--------|------|------|------|--------|

标记使用率 > 80% 的分区。

### 九、告警汇总

| 级别 | 项目 | 详情 | 建议 |
|------|------|------|------|
| P0 | GPU 温度 > 85°C | GPU 0: 90°C | 检查散热 |
| P1 | 显存使用 > 90% | GPU 0: 72GB/80GB | 清理进程 |
| P2 | 磁盘 > 80% | /data: 85% | 清理空间 |

告警规则：
- GPU 温度 > 85°C → P0
- 显存占用 > 90% → P1
- GPU 功耗 > 功耗上限 90% → P1
- 磁盘使用 > 80% → P2
- 内存可用 < 20% → P2
- ECC 错误 > 0 → P1

无异常 → 输出"所有检查项正常"。

## 守护栏

- 所有操作只读，禁止执行任何修改命令
- 禁止输出密码、密钥、Token 等敏感信息
- SSH 命令设置超时（单条命令 10 秒），防止卡死
- 每个检查项独立执行，某项失败不影响其他项
- 如需 sudo 权限但无权限，标注"权限不足"跳过
