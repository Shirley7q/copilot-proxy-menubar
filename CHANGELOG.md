# 更新记录

## v1.0.0 — 2026-09-08

首次发布独立 macOS 桌面菜单栏 App。

- 在菜单栏通过 Enable / Disable 启动或暂停 Copilot Proxy。
- 显示代理运行、启动、暂停及错误状态。
- 支持登录 Mac 后自动启动，恢复上次保存的开关状态。
- 支持从终端代理切换为 App 后台管理。
- 提供诊断面板、日志和 API 地址复制入口。
- 检查进程身份，避免误停其他程序；提供有大小限制的本地日志。
- 提供 macOS Universal App 的 DMG、ZIP 与 SHA-256 校验文件。

要求 macOS 13+、Node.js 22.19.0+ 和已安装并登录的 Copilot Proxy；底层引擎基于 0.10.0 验证。发行包尚未经过 Apple 公证。Intel Mac 已完成运行及手动操作验证，Apple Silicon 已交叉编译，尚未实机验证。

感谢 [Jer-y/copilot-proxy](https://github.com/Jer-y/copilot-proxy) 提供底层代理能力。
