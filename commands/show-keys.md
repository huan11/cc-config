---
description: 查看指定数据库表的键（主键、唯一键、索引），支持任意 MySQL 连接
---

查看指定 MySQL 表的所有键（PRIMARY KEY、UNIQUE KEY、INDEX），格式化输出。

## 参数

用户应提供：`$ARGUMENTS`

格式：`[连接信息] 库名.表名` 或 `库名.表名`（如果当前对话已有连接信息则可省略）

示例：
- `/show-keys -h hostname -u user -p password winddb.qt_indexquote`
- `/show-keys winddb.qt_indexquote`（使用当前对话中已知的连接信息）

## 执行流程

### 1. 解析参数

从 `$ARGUMENTS` 中提取：
- 连接信息（host、port、user、password）—— 如果参数中未提供，从当前对话上下文中查找
- 数据库名和表名（必须提供，格式为 `库名.表名`）

如果缺少连接信息且对话中也没有，询问用户。

### 2. 查询表键信息

执行以下 SQL：

```sql
SHOW CREATE TABLE 库名.表名\G
```

从输出中提取所有 KEY 相关行（PRIMARY KEY、UNIQUE KEY、KEY/INDEX）。

### 3. 格式化输出

以表格形式展示：

| 类型 | 键名 | 字段 |
|------|------|------|
| PRIMARY KEY | - | `id` |
| UNIQUE KEY | `IX_xxx` | `(col1, col2)` |
| INDEX | `idx_xxx` | `col1` |

### 4. 补充说明

- 指出业务唯一键的含义（哪些字段组合唯一确定一条记录）
- 如果发现重复或冗余索引，提醒用户

### 5. 保存结果到文件

将完整的键信息报告写入 Markdown 文件：

- 路径：`{当前工作目录}/db-keys/{库名}-keys.md`（如果查询单表则为 `{库名}-{表名}-keys.md`）
- 文件内容包含：连接地址（不含密码）、查询时间、所有表的键信息表格、规律总结和冗余索引提醒
- 如果文件已存在则覆盖

## 守护栏

- 只读操作，禁止执行任何写 SQL
- 输出中不展示密码
