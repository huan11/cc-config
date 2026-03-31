SSH 到 Mskl（ssh -p 57014 skl@75695qf080hq.vicp.fun），查询 MySQL 数据库概况，输出结构化报告。

## 步骤

1. 连接 MySQL（容器: mysql, root/root123456）
2. 列出所有业务 Schema（排除 mysql、information_schema、performance_schema、sys）
3. 对每个 Schema 查询：表名、行数、表注释、引擎
4. 对每张表查询字段列表（字段名、类型、注释）
5. 汇总输出

## 输出格式

按 Schema 分组，每个 Schema 下列出表格概览（表名、行数、说明），再逐表列出关键字段。对空表（0行）简要描述即可，对有数据的表重点说明。
