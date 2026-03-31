扫描当前机器上所有正在运行的 Docker 容器，展示状态、端口映射和资源占用。

## 步骤

1. 运行以下命令收集数据：

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

2. 合并两份数据，按容器名对齐，输出 Markdown 表格：

| 容器名 | 镜像 | 状态 | 端口映射 | CPU% | 内存占用 | 内存% |
|--------|------|------|----------|------|----------|-------|

## 标注规则

- `healthy` → ✅，`unhealthy` / `Exited` → ❌
- CPU% > 50% 加粗提醒
- 最后一行汇总：容器总数、健康数、是否有异常
