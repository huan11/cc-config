# 通过 SSH 远程操作 Windows 主机的注意事项

适用：W01 / W146 / W230 等 Windows Server 主机。

远端 shell 默认是 **cmd.exe**（不是 bash，不是 PowerShell），它的解析规则和 Linux 完全不同。下面是反复踩过的坑。

---

## 1. 引号嵌套（最常见的坑）

**症状**：命令 exit code 255，`Connection closed by ... port ...`，看起来像网络问题，其实是远端 shell 把命令解析坏了，SSH session 直接被关闭。

### ❌ 错误：用 `\"` 转义内层双引号

```bash
ssh -p 22332 administrator@lanyang.ddns.net "git -C D:\\repo log -1 --format=\"%h %s\""
```

bash 把 `\"` 转成 `"` 发给远端，到了 cmd.exe 那头变成了一串孤立的 `"`，cmd 不像 bash 会做配对，直接解析失败。

### ✅ 正确：外双内单

```bash
ssh -p 22332 administrator@lanyang.ddns.net "git -C D:\\repo log -1 --format='%h %s'"
```

外层双引号交给本地 bash，内层单引号原样透传给 cmd.exe，git 收到的就是 `%h %s`。

### ✅ 更稳：完全避开嵌套

能用 git 内置 placeholder 不带空格的就不带空格：

```bash
ssh ... "git -C D:\\repo log -1 --pretty=oneline"
```

---

## 2. 路径分隔符

Windows 路径里的 `\` 在 bash 字符串里要加倍：

```bash
# ❌ \v 会被 bash 吞掉或解释
ssh ... "dir D:\v3-latest-code"

# ✅ 双反斜杠
ssh ... "dir D:\\v3-latest-code"

# ✅ 或用正斜杠（Windows 大部分工具都接受）
ssh ... "dir D:/v3-latest-code"
```

git、python、node 这些工具基本都吃正斜杠，**优先用 `/`**。

---

## 3. 命令本身就不一样

cmd.exe 不是 bash，下面这些是 cmd 的写法：

| 任务      | Linux            | Windows (cmd)             |
| --------- | ---------------- | ------------------------- |
| 列目录    | `ls`             | `dir`                     |
| 删文件    | `rm file`        | `del file`                |
| 删目录    | `rm -rf dir`     | `rmdir /s /q dir`         |
| 拷贝      | `cp a b`         | `copy a b` / `xcopy`      |
| 环境变量  | `$VAR` / `${VAR}` | `%VAR%`                   |
| 拼接命令  | `a && b`         | `a && b`（cmd 也支持）    |
| 当前目录  | `pwd`            | `cd`（不带参数）          |

如果想用 Linux 风格的命令，可以显式走 PowerShell 或 Git Bash：

```bash
# 走 PowerShell（注意 -Command 后面也是引号嵌套问题）
ssh ... "powershell -Command \"Get-ChildItem D:/repo\""

# 走 Git Bash（如果远端装了）
ssh ... "C:/Program\\ Files/Git/bin/bash.exe -c 'ls /d/repo'"
```

---

## 4. 编码

Windows 默认 GBK / CP936，中文输出在我们终端里会乱码。

```bash
# 临时切到 UTF-8（仅当前 cmd session）
ssh ... "chcp 65001 && git log --oneline -5"
```

如果是脚本类长命令，建议在脚本头里加 `chcp 65001 >nul`。

---

## 5. 长命令怎么办

引号嵌套 ≥ 2 层就不要硬塞一行了，改成两步：

1. 用 `scp` 把脚本传上去
2. SSH 执行 `cmd /c script.bat` 或 `powershell -File script.ps1`

或者用 here-doc 风格通过 stdin 喂给远端的 shell（避开命令行解析）：

```bash
ssh ... "powershell -Command -" <<'EOF'
Get-ChildItem D:/repo
git -C D:/repo log -1
EOF
```

---

## 6. 排错顺序

远程命令失败时按顺序排查：

1. **先在本地 echo 看一眼**：`echo "ssh ... '...'"`，确认 bash 解析后是不是你想要的样子
2. **再 SSH 一个最简单的命令**：`ssh ... "echo hello"`，验证连接本身没问题
3. **再逐步加复杂度**：先不带引号 → 加单引号 → 加双引号
4. **exit code 255 = SSH 自己挂了**（不是远端命令失败），90% 是引号 / 路径解析问题

---

## 7. 给 Claude 的默认动作

- 给 Windows 主机发命令时，**默认外双内单**，不要用 `\"`
- 路径默认用 `/`，不要写 `\\`
- 命令复杂（≥ 2 层引号 / 多行）时，先建议传脚本而不是硬拼一行
- 看到 `exit 255 + Connection closed`，**先怀疑引号，再怀疑网络**
