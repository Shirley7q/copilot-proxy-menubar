Copilot Proxy Menu Bar v1.1.0 新增 Claude Code 接入，可与 Codex 同时连接本机代理。

### 本次更新

- 新增“配置 Claude Code…”入口，从当前代理读取支持原生 Messages 的 Claude 模型，选择主模型和快速模型后复制启动命令。
- 记住模型选择，并根据模型目录设置 1M 上下文 selector。
- 分别提供 Codex / OpenAI 与 Claude / Anthropic API 地址复制。
- 使用会话级启动配置，保留现有 Claude Code 与 Codex 配置文件。

### 下载安装

下载 `.dmg` 后将 `Copilot Proxy.app` 拖入 Applications，或下载 `.zip` 解压安装。升级前先退出旧版 App。`SHA256SUMS.txt` 提供两个安装包的 SHA-256 校验值。

要求 macOS 13+、Node.js 22.19.0+，以及已安装并完成登录的 `@jer-y/copilot-proxy`；底层引擎基于 0.10.0 验证。安装包不包含 Node.js、代理引擎或 Claude Code。

使用 Claude Code 时，先安装 `claude` 命令。打开菜单栏 App 并点击 Enable，等待 Enabled 后选择“配置 Claude Code…”，复制启动命令并在项目目录的终端中运行。

### 验证范围

- 生命周期、后台接管、状态恢复、日志管理及 Claude 配置自动化测试已通过。
- Claude 测试覆盖模型筛选、模型目录 HTTP 获取、错误处理，以及 Bash / Zsh 启动参数验证。
- Universal App 包含 Intel 与 Apple Silicon，已通过构建和临时签名校验。
- 本机未安装 Claude Code，尚未验证真实客户端对话；Apple Silicon 尚未实机验证。

当前发行包使用临时签名，未经 Apple 公证。若 macOS 阻止首次打开，请在尝试启动后进入“系统设置 → 隐私与安全性”，选择“仍要打开”。

完整说明见 [README](https://github.com/Shirley7q/copilot-proxy-menubar#readme)。感谢 [Jer-y/copilot-proxy](https://github.com/Jer-y/copilot-proxy) 提供底层代理能力。
