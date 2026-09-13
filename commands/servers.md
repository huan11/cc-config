查询 Beszel Hub API，展示所有受监控服务器的实时算力状态。

## 凭据

⚠️ **不入库**。真实值放在 `~/.config/beszel.env`（权限 600，不在任何 git 仓库内）：

```bash
source ~/.config/beszel.env   # 提供 BESZEL_URL / BESZEL_IDENTITY / BESZEL_PASSWORD
```

文件不存在时**停下来告诉用户补齐**，不要猜测、不要硬编码。

## 执行步骤

1. 调用 Beszel Hub 认证 API 获取 token（口令经 stdin 进 curl，不出现在命令行和 shell 历史里）：

```bash
source ~/.config/beszel.env
TOKEN=$(python3 - <<'PY'
import json, os, urllib.request
body = json.dumps({"identity": os.environ["BESZEL_IDENTITY"],
                   "password": os.environ["BESZEL_PASSWORD"]}).encode()
req = urllib.request.Request(
    f'{os.environ["BESZEL_URL"]}/api/collections/users/auth-with-password',
    data=body, headers={"Content-Type": "application/json"}, method="POST")
print(json.loads(urllib.request.urlopen(req).read())["token"])
PY
)
```

2. 用 token 调用系统列表 API：

```
GET $BESZEL_URL/api/collections/systems/records
Header: Authorization: Bearer <token>
```

3. 解析每台机器的 `info` 字段，按以下格式输出表格：

| 名称 | IP | 状态 | CPU 核数 | CPU% | 内存% | 磁盘% | 负载(1/5/15) | Agent |
|------|-----|------|---------|------|-------|-------|-------------|-------|

字段映射：
- `info.t` → CPU 核数
- `info.cpu` → CPU 使用率%
- `info.mp` → 内存使用率%
- `info.dp` → 磁盘使用率%
- `info.la` → 负载数组 [1min, 5min, 15min]
- `info.v` → Agent 版本
- `status` → up/down

4. 表格下方附上 Dashboard 链接：`$BESZEL_URL`

## 注意事项

- 使用 bash curl 命令执行 API 调用，用 python3 -m json.tool 格式化
- 如果有机器 status 为 down，用加粗标注提醒
- 保持输出简洁，一个表格搞定
