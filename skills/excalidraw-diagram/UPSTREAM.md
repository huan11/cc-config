# 来源与本地改动

本 skill 是第三方的，**不是自建**。

| 项 | 内容 |
|---|---|
| 上游 | https://github.com/coleam00/excalidraw-diagram-skill |
| 取自上游 commit | `8646fcc`（"Better setup"，2026-03-01） |
| 并入本仓时间 | 2026-09-13 |

## 为什么不做 submodule

并入时它有**未提交的本地改动**（见下），submodule 只跟踪 commit，捕获不到这些改动，
会让归档出现静默的洞。因此去掉嵌套 `.git`，文件直接并入 `~/.claude` 仓。
上游那 2 个 commit 的完整历史在 `~/Documents/cc-skills-2026-09-13.zip` 里另有备份。

## 相对上游的本地改动

- `references/render_excalidraw.py` — 已修改
- `references/render_template.html` — 已修改
- `references/package.json` / `package-lock.json` — 本地新增（node 渲染链）
- `references/render_excalidraw.py.bak` — 本地备份文件

## 依赖不入库

`references/.venv/`（Python + playwright，约 136 MB）和 `references/node_modules/`（约 130 MB）
已 gitignore。新机器上按 `uv.lock` / `pyproject.toml` / `package-lock.json` 重装。
