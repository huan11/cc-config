在 W01 上拉取指定项目的最新代码。

参数: $ARGUMENTS（项目名称）

## 映射规则

项目名即 W01 上的目录名，代码统一放在 `D:\00-v4-latest-code\` 下。

例如参数 `v4-email-download-230` → W01 目录 `D:\00-v4-latest-code\v4-email-download-230`

## 执行步骤

1. 先检测当前项目本地是否有未提交的代码（`git status`），如果有则提醒用户先提交
2. SSH 到 W01 执行：
   ```bash
   ssh -p 22332 administrator@lanyang.ddns.net "cd D:/00-v4-latest-code/$ARGUMENTS; git pull"
   ```
3. 展示拉取结果（更新了哪些文件）
