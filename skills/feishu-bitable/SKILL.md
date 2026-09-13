---
name: feishu-bitable
description: 当需要读写飞书/Lark 多维表格(Bitable / Base)时用——列出表、读字段、读记录、新增/修改列(字段)、批量回填记录、新建视图并设过滤条件等。触发信号:用户给了 feishu.cn/base/... 链接、说"多维表格/Base/飞书表格"、要"加一列/加个视图/按 X 过滤/回填数据"。本 skill 记录了走通的鉴权流程与几个必踩的坑(scope、过滤 value 格式、单选用 option id),避免每次重新试错。不用于:普通 MySQL/Excel、飞书文档(docx)、飞书云表格(sheets,那是另一套接口)。
metadata:
  version: "1.1.0"
  updated: "2026-08-24"
---

# feishu-bitable — 飞书多维表格读写

用命令行工具 **`lark-cli`**(不是 lark-mcp)操作。lark-mcp 那条路的坑:租户 token 常 `91403`(应用非该 Base 协作者),OAuth 登录又卡在重定向 URL `20029`。`lark-cli` 用自带应用走 device flow,最省事。

## 0. 通用调用形态

```bash
lark-cli api <GET|POST|PUT|PATCH|DELETE> <path> \
  --params '<url查询参数JSON>' --data '<请求体JSON>' --as user
```
- `--as user`:用用户身份(拿你本人在该 Base 的权限)。
- `--params` 给 query(如 `page_size`/`view_id`),`--data` 给 body。
- 返回是 JSON,失败时 `{"ok":false,"error":{...}}`;成功 `{"code":0,...}`。

## 1. 鉴权(第一次 / token 过期时)——★最容易卡的一步

lark-cli 用它**自带的应用**(非你自己的应用),token 有效期 ~2h、refresh ~7d。查状态:`lark-cli auth status`。

**读记录需要老式 scope `base:record:retrieve` + `bitable:app:readonly`**,而 `--domain base` 只给 `base:record:read`(不够!)。所以必须显式点名请求:

```bash
# 1) 发起 device flow(不阻塞,拿 URL + device_code)
lark-cli auth login --scope "bitable:app:readonly base:record:retrieve base:record:read base:field:create base:record:update base:view:read base:view:write_only base:table:read" --no-wait
# 2) 浏览器打开返回的 verification_url(带 user_code),用户确认授权
open "<verification_url>"
# 3) 用返回的 device_code 完成登录(阻塞到授权完成,建议后台跑)
lark-cli auth login --device-code "<device_code>"
```
> 授权页里确认新 scope 在列。完成后 `lark-cli api ... /records` 才不再 `99991679 Permission denied`。

## 2. 读(app_token 就是 URL 里 `/base/` 后那段;table_id 是 `?table=` 那段)

```bash
A=<app_token>; T=<table_id>
lark-cli api GET /open-apis/bitable/v1/apps/$A/tables --params '{"page_size":100}' --as user      # 列出所有表
lark-cli api GET /open-apis/bitable/v1/apps/$A/tables/$T/fields --params '{"page_size":100}' --as user   # 列字段(拿 field_id、单选 option id)
lark-cli api GET /open-apis/bitable/v1/apps/$A/tables/$T/records --params '{"page_size":200}' --as user   # 读记录
```
> **坑**:别用 `--page-all`,它把多页拼成非标准 JSON 解析会炸;行多就手动翻页(带 `page_token`)。

## 3. 新增列(字段)

```bash
# 文本列 type=1;单选 type=3;数字 type=2;多选 type=4;日期 type=5;复选 type=7 …
lark-cli api POST /open-apis/bitable/v1/apps/$A/tables/$T/fields \
  --data '{"field_name":"归属系统","type":3,"property":{"options":[{"name":"拦截系统"},{"name":"分离系统"}]}}' --as user
```
**给已有单选列加选项**:用 `PUT .../fields/{field_id}`,body 里要带**全部**已有选项(含各自 `id`)+ 新选项(新的不带 id)。漏带某个已有 id 会把它改没/重命名。先 GET fields 拿现有 options 的 id 再拼。

## 4. 批量回填记录

```bash
# body:{"records":[{"record_id":"rec...","fields":{"列名":"值"}}, ...]}(单选/文本列直接给字符串值)
lark-cli api POST /open-apis/bitable/v1/apps/$A/tables/$T/records/batch_update \
  --data "$(cat /tmp/batch.json)" --as user
```
行多时用 Python 读一次 records、按关键词映射、生成 batch.json,再一把提交(见下方模式)。

## 5. 新建视图 + 设过滤 ——★两个必踩的坑

```bash
# 5a. 建视图(grid 网格),拿 view_id
lark-cli api POST /open-apis/bitable/v1/apps/$A/tables/$T/views \
  --data '{"view_name":"拦截系统","view_type":"grid"}' --as user
# 5b. 设过滤:PATCH 视图,写 property.filter_info
lark-cli api PATCH /open-apis/bitable/v1/apps/$A/tables/$T/views/<view_id> \
  --data '{"property":{"filter_info":{"conjunction":"and","conditions":[{"field_id":"<fld...>","operator":"is","value":"[\"<opt...>\"]"}]}}}' --as user
```
- **坑1 · value 必须是"字符串化的 JSON 数组"**,不是数组本身。给数组 → `9499 Invalid parameter type`。正确:`"value":"[\"...\"]"`。
- **坑2 · 单选/多选的 value 里放 option id(optXXX),不是选项名**。放名字 → `1254001 option id not found`。option id 从 GET fields 拿。
- 常用 operator:`is` / `isNot` / `contains` / `isEmpty` / `isNotEmpty` / `isGreater` …
- **验证视图行数**:`GET .../records --params '{"view_id":"vew...","page_size":200}'`;**0 行的视图返回体没有 `items` 键**(不是报错)。

## 6. 批量回填的可复用模式(Python 生成 body)

```python
import json
d = json.load(open('records.json'))           # 先 GET records 存这里
def txt(v):                                     # 文本单元格取纯文本
    if isinstance(v, list): return ''.join(x.get('text','') if isinstance(x,dict) else str(x) for x in v)
    if isinstance(v, dict): return v.get('text','')
    return '' if v is None else str(v)
recs = []
for it in d['data']['items']:
    kw = txt(it['fields'].get('关键词',''))
    recs.append({'record_id': it['record_id'], 'fields': {'归属系统': my_map(kw)}})
json.dump({'records': recs}, open('/tmp/batch.json','w'), ensure_ascii=False)
```

## 7. 新建 Base + 放置(个人 / 共享文件夹 / 知识库)+ 删除

**核心事实(必记):用用户 token 建的 Base,owner 恒为你本人**。放进共享文件夹只是"共享给成员",owner 不变(面包屑一直挂你名下)。要**去个人化(团队所有)**,只有两条路:①移进**知识库(Wiki)**,owner 变成知识库空间;②**转移所有者**给别人。

```bash
# 7a. 建库。folder_token 空 → 落"我的空间"(挂你名下);带上共享文件夹 token → 直接建到共享文件夹(仍属你、已共享)
lark-cli api POST /open-apis/bitable/v1/apps \
  --data '{"name":"表名","folder_token":"<共享文件夹token或空串>"}' --as user
# 返回 data.app.{app_token, default_table_id, url}

# 7b. 去个人化:把 Base 移进知识库(Wiki),owner→知识库空间。异步返 task_id,完成后 URL 从 /base/ 变 /wiki/<node>
lark-cli api GET  /open-apis/wiki/v2/spaces --params '{"page_size":50}' --as user        # 先列知识库拿 space_id
lark-cli api POST /open-apis/wiki/v2/spaces/<space_id>/nodes/move_docs_to_wiki \
  --data '{"obj_type":"bitable","obj_token":"<app_token>"}' --as user

# 7c. 移到普通(共享)文件夹
lark-cli api POST /open-apis/drive/v1/files/<app_token>/move \
  --data '{"type":"bitable","folder_token":"<folder_token>"}' --as user

# 7d. 删库
lark-cli api DELETE /open-apis/drive/v1/files/<app_token> --params '{"type":"bitable"}' --as user
```
- **拿共享文件夹的 `folder_token`**:浏览器打开该文件夹,URL 里 `/drive/folder/XXXX` 的 `XXXX` 就是;API 列云盘/文件夹要 `drive:drive`(见权限表)。
- **坑 · `--domain base` 授权不含建/删/移/wiki 这些 scope**,直接调会 `99991679 missing_scope`,报错 hint 里会给出要补的 scope 和现成的 `lark-cli auth login --scope "..." --no-wait --json` 命令——照做发链接给用户,授权后 `--device-code` 续上(见 §1)。
- **移进 Wiki 后再操作**:用 `/wiki/<node_token>` 链接给人;但 API 仍用原 `app_token`(不变)。

## 权限速查(读写各需什么 scope)

| 操作 | 需要的 scope |
|------|-------------|
| 列表/字段 | `base:table:read` / `base:field:read`(`--domain base` 已含) |
| **读记录** | `base:record:retrieve` **或** `bitable:app:readonly`(需显式请求,见 §1) |
| 建/改字段 | `base:field:create` / `base:field:update` |
| 写记录 | `base:record:update` / `base:record:create` |
| 建/改视图 | `base:view:write_only` |
| **建/改库** | `base:app:create` / `base:app:update` |
| **移到文件夹** | `space:document:move` |
| **列云盘/文件夹** | `drive:drive` 或 `drive:drive:readonly` + `space:document:retrieve` |
| **删库** | `drive:drive` + `space:document:delete` |
| **移进知识库(Wiki)** | `wiki:wiki` + `wiki:node:move`(+ `wiki:node:create`);列知识库 `wiki:space:read` |
| **转移所有者** | `docs:permission.member:transfer` |

## 本机常用 Base / 组织

- **青云梯组织** = 子域 `bcnqv09m4ahm.feishu.cn`(tenant `1aef1c76faca1be2`)。lark-cli 用户 token 就在青云梯里操作,返回显示名「用户067919」只是本人昵称,**不是**另一个组织。
  - 共享文件夹「DMS项目文档」`folder_token = SYT6fbB3alqJdbdWLEacl1GOn5d`(直建到共享文件夹用它)
  - 知识库「测试知识库」`space_id = 7668895835848969478`(移进 Wiki 去个人化用它)
- **DMS 净烟 · 硬件/DTU 参考库**:app_token `EfkEbq59Hao5rusCXeVcLmeRnTe`
  - `DTU V3.1`(30 字段协议+归属系统) `tbl18HYhfyPRGZTI`;另有 `硬件信息`/`硬件接口字段`/`域名`/`更新日志`。
