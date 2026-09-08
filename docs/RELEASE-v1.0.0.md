Copilot Proxy Menu Bar 的首个正式版本：一款独立的 macOS 桌面菜单栏 App，通过 **Enable / Disable** 控制本地 Copilot Proxy 是否启用。

### 主要功能

- 菜单栏一键启停，并显示运行状态。
- 后台运行与终端进程接管。
- 登录 Mac 自动启动，恢复上次的开关状态。
- 一键打开诊断面板、查看日志、复制 API 地址。

### 下载安装

下载下面的 `.dmg`，打开后将 App 拖入 Applications；也可以下载 `.zip` 解压安装。`SHA256SUMS.txt` 提供文件校验值。

**系统要求：** macOS 13 或更新版本，Node.js 22.19.0+，以及已安装并完成登录的 `@jer-y/copilot-proxy`。本版本基于代理引擎 0.10.0 验证；安装包不包含 Node.js 或代理引擎。

**架构：** Universal App，包含 Intel 与 Apple Silicon。Intel Mac 已通过运行和手动操作测试，Apple Silicon 版本已交叉编译，尚未实机验证。

**首次打开：** 本版本使用临时签名，未经 Apple 公证。如 macOS 阻止打开，请在尝试启动后进入“系统设置 → 隐私与安全性”，选择“仍要打开”。

### 使用提示

打开 App 后，点击右上角闪电图标。首次运行默认注册登录项，可在菜单中关闭。已有终端代理会保持运行；点击“切换到后台运行”后即可关闭终端，切换会短暂重启代理。

完整使用说明见 [README](https://github.com/Shirley7q/copilot-proxy-menubar#readme)。感谢 [Jer-y/copilot-proxy](https://github.com/Jer-y/copilot-proxy) 提供底层代理能力。
