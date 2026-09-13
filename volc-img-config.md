查询火山引擎镜像仓库（Volcengine Container Registry），支持列出命名空间、镜像仓库、镜像版本。

## 用法

- `/volc-img-config` — 列出所有命名空间及其下的镜像
- `/volc-img-config tags app/dms-admin` — 查看指定镜像的 tag 列表
- `/volc-img-config pull app/dms-admin:latest` — 生成 docker pull 命令
- `/volc-img-config login` — 在当前/指定服务器上执行 docker login
- `/volc-img-config login L68` — 在 L68 上远程执行 docker login

## 认证信息

⚠️ **凭据不入库**。真实值放在 `~/.config/volc-cr.env`（权限 600，不在任何 git 仓库内）：

```bash
source ~/.config/volc-cr.env   # 提供 VOLC_AK / VOLC_SK / VOLC_DOCKER_PASSWORD
```

| 项 | 值 |
|---|---|
| AK | `$VOLC_AK` |
| SK | `$VOLC_SK` |
| Registry 实例 | `beansinfo` |
| Region | `cn-beijing` |
| Docker 地址 | `beansinfo-cn-beijing.cr.volces.com` |
| Docker 用户名 | `asher@67629797` |
| Docker 密码 | `$VOLC_DOCKER_PASSWORD` |

若该文件不存在，**停下来告诉用户补齐**，不要猜测、不要硬编码、不要写进任何文件。

## API 调用方法

使用 Python3 标准库调用火山引擎 OpenAPI，签名方式为 HMAC-SHA256。
运行前先 `source ~/.config/volc-cr.env`，脚本从环境变量取凭据：

```python
import os, hashlib, hmac, datetime, urllib.request, urllib.parse, ssl, json

ak = os.environ["VOLC_AK"]   # 缺失会直接 KeyError，不静默用错凭据
sk = os.environ["VOLC_SK"]
service, region, host = "cr", "cn-beijing", "open.volcengineapi.com"

def volcr_api(action, body=None):
    now = datetime.datetime.now(datetime.UTC)
    ds, ad = now.strftime('%Y%m%d'), now.strftime('%Y%m%dT%H%M%SZ')
    query = urllib.parse.urlencode({"Action": action, "Version": "2022-05-12"})
    bb = json.dumps(body or {}).encode()
    ch, sh = f"host:{host}\nx-date:{ad}\n", "host;x-date"
    ph = hashlib.sha256(bb).hexdigest()
    cr = f"POST\n/\n{query}\n{ch}\n{sh}\n{ph}"
    cs = f"{ds}/{region}/{service}/request"
    sts = f"HMAC-SHA256\n{ad}\n{cs}\n{hashlib.sha256(cr.encode()).hexdigest()}"
    def s(k, m): return hmac.new(k, m.encode(), hashlib.sha256).digest()
    sig = hmac.new(s(s(s(s(sk.encode(), ds), region), service), "request"), sts.encode(), hashlib.sha256).hexdigest()
    auth = f"HMAC-SHA256 Credential={ak}/{cs}, SignedHeaders={sh}, Signature={sig}"
    req = urllib.request.Request(f"https://{host}/?{query}", data=bb, method="POST",
        headers={"Host": host, "X-Date": ad, "Authorization": auth, "Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, context=ssl.create_default_context()).read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())
```

## 可用 API Action

| Action | 参数 | 说明 |
|--------|------|------|
| ListRegistries | 无 | 列出实例 |
| ListNamespaces | `{"Registry": "beansinfo"}` | 列出命名空间 |
| ListRepositories | `{"Registry": "beansinfo", "Namespace": "<ns>"}` | 列出镜像仓库 |
| ListTags | `{"Registry": "beansinfo", "Namespace": "<ns>", "Repository": "<repo>"}` | 列出镜像版本 |

## Docker 登录与拉取

### 登录凭证

- 用户名: `asher@67629797`
- 密码: `$VOLC_DOCKER_PASSWORD`（来自 `~/.config/volc-cr.env`）
- Registry: `beansinfo-cn-beijing.cr.volces.com`

### 登录命令

用 `--password-stdin`，不要用 `--password`——后者会把口令留在 shell 历史和远端 `ps` 输出里。

```bash
source ~/.config/volc-cr.env

# 本地执行
echo "$VOLC_DOCKER_PASSWORD" | docker login \
  --username=asher@67629797 --password-stdin beansinfo-cn-beijing.cr.volces.com

# 远程执行（以 L68 为例）：口令经 stdin 穿过 ssh，不出现在远端命令行里
echo "$VOLC_DOCKER_PASSWORD" | ssh root@47.102.142.68 \
  "docker login --username=asher@67629797 --password-stdin beansinfo-cn-beijing.cr.volces.com"
```

### 拉取命令

```bash
docker pull beansinfo-cn-beijing.cr.volces.com/<namespace>/<repository>:<tag>
# 例: docker pull beansinfo-cn-beijing.cr.volces.com/app/dms-admin:latest
```

注意: 此镜像仓库为国内（火山引擎北京），直连即可，不需要走代理。

## 执行步骤

1. 根据用户参数决定执行什么操作
2. **无参数**: 调用 ListNamespaces + ListRepositories，输出所有命名空间及镜像列表
3. **tags <ns/repo>**: 调用 ListTags，输出镜像的所有 tag
4. **pull <ns/repo:tag>**: 在目标服务器上执行 docker login（如未登录）+ docker pull
5. **login [服务器]**: 在指定服务器上执行 docker login，无参数则本地执行
6. 用表格格式展示结果

## 注意事项

- 使用 python3 内联脚本调用 API（不依赖第三方库）
- API 签名必须用 HMAC-SHA256，POST 方法，body 为 JSON
- 镜像完整地址格式: `beansinfo-cn-beijing.cr.volces.com/<namespace>/<repository>:<tag>`
- 此镜像仓库是国内服务，不需要走代理，直连即可
