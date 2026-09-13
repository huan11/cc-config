给当前 Python 项目添加飞书卡片通知，风格与 v3-score-update / v3-trading / v3-oss-update-rank 保持一致。

**参数**：`/feishu-notifier [webhook_url]`

- `webhook_url`：可选，直接传入 Webhook URL；不传则从 `.env` 读取或提示用户填写

---

## 卡片规范（所有项目统一）

```
msg_type: interactive
card:
  header:  title（项目名 + 日期）+ template（blue=成功 / red=异常 / green=dry-run）
  elements:
    - tag: div  →  lark_md 内容（Markdown 表格展示关键指标）
    - tag: note →  plain_text 时间戳
```

---

## Phase 1：扫描项目结构

读取当前工作目录，搞清楚以下几件事：

1. **源码包路径**：找 `src/<pkg>/` 或 `<pkg>/`，确定 `notifier.py` 放哪
2. **主入口文件**：找 `run_*.py` / `*_main.py` / `__main__.py` / `cli.py`，确定在哪里调用通知
3. **写库操作**：grep `写入` / `INSERT` / `df_to_sql` / `rows_written`，提取关键表名和行数变量
4. **已有通知代码**：检查是否已有 `notifier.py` 或 `FeishuSender`，避免重复
5. **`.env` 文件**：检查是否已有 `FEISHU_WEBHOOK_URL`
6. **logger 名称**：从现有 `logging.getLogger(...)` 读取，或用包名

把扫描结果列给孟老板确认，格式如下：

```
扫描结果：
  源码包:    src/score_update/
  notifier:  src/score_update/notifier.py（新建）
  主入口:    src/score_update/cli.py
  关键指标:  score_data_score（行数）、opt_portfolio（行数）
  logger:    score_update
  .env:      已有 FEISHU_WEBHOOK_URL ✅ / 未配置 ❌
```

如有不确定的地方，问清楚再动手。

---

## Phase 2：确认 Webhook URL

按优先级检查：

1. 命令参数直接传入
2. `.env` 里已有 `FEISHU_WEBHOOK_URL`
3. 问孟老板要

拿到后写入 `.env`（若未配置）。

---

## Phase 3：生成 notifier.py

在确定的路径创建 `notifier.py`，内容模板如下（按实际项目调整）：

```python
"""飞书 Webhook 通知。"""

import logging
import os
from datetime import datetime

import requests

logger = logging.getLogger("<pkg_name>")

_TIMEOUT = 10


def _send_card(webhook_url: str, title: str, content: str, template: str = "blue") -> None:
    if not webhook_url:
        return
    payload = {
        "msg_type": "interactive",
        "card": {
            "header": {
                "title": {"tag": "plain_text", "content": title},
                "template": template,
            },
            "elements": [
                {
                    "tag": "div",
                    "text": {"tag": "lark_md", "content": content},
                },
                {
                    "tag": "note",
                    "elements": [
                        {
                            "tag": "plain_text",
                            "content": f"通知时间: {datetime.now():%Y-%m-%d %H:%M:%S}",
                        }
                    ],
                },
            ],
        },
    }
    try:
        resp = requests.post(webhook_url, json=payload, timeout=_TIMEOUT)
        if resp.status_code == 200:
            logger.info("飞书通知发送成功: %s", title)
        else:
            logger.warning("飞书通知失败: %s %s", resp.status_code, resp.text)
    except Exception:
        logger.exception("飞书通知异常: %s", title)


def send_<project>_success(
    webhook_url: str,
    target_date: str,
    elapsed: float,
    # ↓ 按实际指标调整参数
    rows_written: dict[str, int],
) -> None:
    """发送运行完成通知。"""
    table_lines = "\n".join(f"| {k} | {v} |" for k, v in rows_written.items())
    content = (
        f"**日期:** {target_date}　　**耗时:** {elapsed:.0f}s\n\n"
        f"**写入明细**\n"
        f"| 表名 | 行数 |\n"
        f"| --- | --- |\n"
        f"{table_lines}"
    )
    _send_card(webhook_url, f"<Project> 运行完成 {target_date}", content, template="blue")


def send_<project>_error(webhook_url: str, target_date: str, errors: list[str]) -> None:
    """发送异常通知。"""
    error_lines = "\n".join(f"- {e}" for e in errors)
    content = f"**日期:** {target_date}\n\n**错误详情**\n{error_lines}"
    _send_card(webhook_url, f"<Project> 运行异常 {target_date}", content, template="red")
```

**适配要点：**
- `<pkg_name>` → 实际包名
- `send_<project>_success` 的参数 → 反映项目真正关心的指标（行数、产品数、任务数等）
- 表格标题、列名贴近业务语言（不要写"key/value"这种通用词）

---

## Phase 4：修改主入口

在主入口文件的 `if __name__ == "__main__":` 块（或 CLI 入口函数）里做以下三件事：

### 4a. 导入通知函数
```python
from <pkg>.notifier import send_<project>_success, send_<project>_error
```

### 4b. 包 try/except，收集 errors
```python
t0 = time.time()
errors = []

try:
    run_step_a()
except Exception as e:
    errors.append(f"step_a: {e}")
    logger.exception("step_a 失败")

# ... 其他步骤同理

elapsed = time.time() - t0
```

### 4c. 结束时发通知
```python
webhook = os.getenv("FEISHU_WEBHOOK_URL", "")

if errors:
    send_<project>_error(webhook, target_date, errors)
else:
    rows = collect_metrics()   # 查 DB 或从运行结果汇总
    send_<project>_success(webhook, target_date, elapsed, rows)
```

**收集指标的原则：**
- 优先从函数返回值取（最可靠）
- 其次运行后查 DB（`SELECT COUNT(*) ... WHERE date = target_date`）
- 不要解析 print 输出

---

## Phase 5：测试

用最简单的方式验证通知能发出去：

```bash
uv run python -c "
import os; from dotenv import load_dotenv; load_dotenv('.env')
from <pkg>.notifier import send_<project>_success
send_<project>_success(os.getenv('FEISHU_WEBHOOK_URL'), 'TEST', 1.0, {'test_table': 99})
"
```

看到日志 `飞书通知发送成功` 即完成。

---

## 注意事项

- **不要动其他文件**——只改主入口和新建 notifier.py，不重构业务逻辑
- **幂等**——已有 notifier.py 的项目，只补缺失函数，不覆盖已有实现
- **不要 print 调试信息**——`FeishuSender` 那个旧类会打印 "=== 配置信息 ===" 这类噪音，新 notifier 一律用 `logger`
- **webhook 不写死在代码里**——始终从 `os.getenv("FEISHU_WEBHOOK_URL")` 读取
