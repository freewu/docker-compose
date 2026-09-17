# AGENTS.md

本文件记录本仓库的协作约定，AI/协作者修改代码时都必须遵守。

## 强制规则

1. **每次修改完成后，必须 `git commit` 并 `git push` 到远程（origin）**，不要只改文件不提交。

   ```bash
   git add <改动的文件>
   git commit -m "<类型>: <简短说明>"
   git push origin main
   ```

2. 提交前先 `git status` / `git diff` 自查，确认只提交本次真正改动的内容。

## 仓库约定

- 一个中间件一个目录：`<service>/docker-compose.yml`，配置文件放 `<service>/config/`。
- 宿主机数据目录统一用 `/data/<service>`，容器内挂载到镜像自身的默认数据目录。
- 配置文件尽量挂到镜像支持的 `conf.d` / `config.d` 目录，不要整文件覆盖镜像自带的默认配置。
- 文件换行符统一使用 **LF**（GitHub 上的源文件均为 LF）。
  - Windows 上把文件批量转成 CRLF 会产生大量无意义 diff，提交前请清理。
  - 如确有需要，可单独提一个规范化提交，不要混在功能修改里。

## 提交信息格式

`<类型>: <说明>`，类型用：`feat` / `fix` / `docs` / `chore` / `refactor`。
