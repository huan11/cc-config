为当前项目生成飞书机器人通知模块，开箱即用。

## 参考实现

以下代码来自已验证的生产环境，作为生成模块的**唯一参考蓝本**。

### 消息构建（富文本 post 格式）

```python
def build_feishu_message(title, content_lines):
    """
    构建飞书富文本消息。

    Args:
        title: 消息标题，如 "⚠️ 数据异常告警 [2026-03-11 14:30:45]"
        content_lines: 内容行列表，每行是一个 list[dict]
            示例: [[{"tag": "text", "text": "第一段内容\n"}],
                   [{"tag": "text", "text": "第二段内容\n"}]]

    Returns:
        dict: 飞书 post 类型消息体
    """
    return {
        "msg_type": "post",
        "content": {
            "post": {
                "zh_cn": {
                    "title": title,
                    "content": content_lines,
                }
            }
        },
    }
```

### 消息发送

```python
import requests

def send_feishu_notification(webhook_url, message):
    """发送飞书 Webhook 通知。"""
    try:
        resp = requests.post(webhook_url, json=message, timeout=10)
        if resp.status_code == 200:
            result = resp.json()
            if result.get("code") == 0 or result.get("StatusCode") == 0:
                print("飞书通知发送成功")
                return True
            else:
                print(f"飞书通知发送失败: {result}")
                return False
        else:
            print(f"飞书通知 HTTP 错误: {resp.status_code}")
            return False
    except Exception as e:
        print(f"飞书通知发送异常: {e}")
        return False
```

### 飞书消息富文本标签参考

```python
# 纯文本
{"tag": "text", "text": "内容\n"}

# 超链接
{"tag": "a", "text": "链接文字", "href": "https://example.com"}

# 加粗（用 text 拼接 ** 无效，飞书 post 不支持 markdown，只能用 tag）
# 飞书 post 格式本身不支持加粗，如需加粗请使用 interactive card 格式

# @ 某人
{"tag": "at", "user_id": "ou_xxx"}

# @ 所有人
{"tag": "at", "user_id": "all"}
```

### 交互式卡片格式（可选，用于需要按钮、分栏等复杂场景）

```python
def build_card_message(title, elements, header_color="blue"):
    """
    构建飞书交互式卡片消息。

    Args:
        title: 卡片标题
        elements: 卡片元素列表
        header_color: 标题颜色，可选 blue/green/red/orange/purple/indigo/grey

    Returns:
        dict: 飞书 interactive 类型消息体
    """
    return {
        "msg_type": "interactive",
        "card": {
            "header": {
                "title": {"tag": "plain_text", "content": title},
                "template": header_color,
            },
            "elements": elements,
        },
    }

# 卡片元素示例
# Markdown 文本块
{"tag": "div", "text": {"tag": "lark_md", "content": "**加粗** 普通文本 [链接](url)"}}

# 分割线
{"tag": "hr"}

# 备注
{"tag": "note", "elements": [{"tag": "plain_text", "content": "备注内容"}]}
```

## 执行流程

### 第 1 步：了解需求

向用户确认以下信息：

1. **Webhook URL**：飞书群机器人的 Webhook 地址
   - 如果用户未提供，生成代码时使用占位符 `YOUR_WEBHOOK_URL`，并在代码注释中提醒替换
2. **使用场景**：用户打算用这个模块做什么（告警通知 / 定时报告 / 任务通知 等）
3. **消息风格偏好**：
   - 富文本（post）：适合简单通知、告警，开发简单（推荐）
   - 交互式卡片（interactive）：适合需要按钮、分栏、Markdown 的复杂消息
4. **模块放置位置**：用户希望文件放在项目的哪个目录下（默认项目根目录）

### 第 2 步：生成模块文件

基于用户需求，生成 `feishu_bot.py` 模块文件。

**文件结构要求：**

```python
"""
飞书机器人通知模块
提供飞书 Webhook 消息发送能力，支持富文本和交互式卡片两种格式。
"""

import requests
from datetime import datetime

# ============= 配置 =============

FEISHU_WEBHOOK_URL = "用户提供的URL或占位符"

# ============= 消息构建 =============

def build_text_message(text):
    """构建纯文本消息。"""
    ...

def build_post_message(title, content_lines):
    """构建富文本消息。"""
    ...

def build_card_message(title, elements, header_color="blue"):
    """构建交互式卡片消息（如用户需要）。"""
    ...

# ============= 发送 =============

def send(message, webhook_url=None):
    """发送消息到飞书。webhook_url 为空时使用模块级默认地址。"""
    ...

# ============= 便捷方法 =============

def notify(text, title=None):
    """快捷发送通知。有标题用富文本，无标题用纯文本。"""
    ...

def alert(title, details, level="warning"):
    """快捷发送告警。level: info/warning/error。"""
    ...
```

**代码规范：**
- 严格参照「参考实现」中的消息格式和发送逻辑，不自行发明 API 调用方式
- `send()` 函数必须包含完整的错误处理（HTTP 状态码检查 + JSON 响应验证 + 异常捕获）
- Webhook URL 支持模块级默认值和函数参数覆盖两种方式
- 只依赖 `requests` 标准库，不引入额外依赖
- 不过度封装，保持代码直观可读

### 第 3 步：生成使用示例

在模块文件底部的 `if __name__ == '__main__'` 中添加可直接运行的示例：

```python
if __name__ == '__main__':
    # 示例1：纯文本
    send(build_text_message("测试消息"))

    # 示例2：富文本告警
    alert("数据异常", "realtime_xxx 表超过2分钟未更新", level="warning")

    # 示例3：快捷通知
    notify("任务执行完成", title="定时任务")
```

### 第 4 步：集成指引

告诉用户如何在项目中使用：

```python
from feishu_bot import notify, alert, send, build_post_message

# 快捷通知
notify("数据处理完成")

# 告警
alert("异常告警", "xxx 服务无响应", level="error")

# 自定义富文本
msg = build_post_message("日报", [
    [{"tag": "text", "text": "今日处理数据 1000 条\n"}],
    [{"tag": "text", "text": "异常 0 条\n"}],
])
send(msg)
```

如果模块不在项目根目录，提示用户调整 import 路径或添加 `sys.path`。

## 守护栏

- 消息格式严格遵循参考实现，不自行猜测飞书 API 字段
- 不在代码中硬编码敏感信息（用户未提供 Webhook URL 时使用占位符）
- 生成的模块必须能独立运行（`python feishu_bot.py` 可执行示例）
- 不引入 `requests` 之外的额外依赖
- 只生成一个文件，不拆分为多个模块
- 代码量控制在 150 行以内，避免过度封装
