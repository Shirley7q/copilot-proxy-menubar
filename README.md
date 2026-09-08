<p align="center">
  <img src="docs/app-icon.png" width="112" alt="Copilot Proxy Menu Bar 图标">
</p>

<h1 align="center">Copilot Proxy Menu Bar</h1>

<p align="center">Mac 菜单栏里的 Copilot Proxy 开关。</p>

<p align="center">
  <a href="https://github.com/Shirley7q/copilot-proxy-menubar/releases/latest">下载 App</a> ·
  <a href="#开始使用">开始使用</a> ·
  <a href="#致谢">致谢</a>
</p>

**Copilot Proxy Menu Bar 是一款独立的 macOS 桌面菜单栏 App，用来控制本机 Copilot Proxy 功能是否启用。** 点击菜单栏图标，即可通过 **Enable / Disable** 开启或暂停代理，查看运行状态，并设置登录 Mac 后自动启动。

完成首次环境准备后，日常使用只需点菜单栏开关，无需一直开着终端或重复输入启动命令。

## 它能做什么

| 功能 | 使用体验 |
| --- | --- |
| **Enable / Disable** | 一键启动或停止本地代理 |
| **菜单栏状态** | 查看已启用、已暂停、正在启动或需要处理的状态 |
| **后台运行** | 由 App 管理代理进程，启动后可以关闭终端 |
| **接管终端进程** | 将已经在终端运行的代理切换为 App 后台管理 |
| **登录自启** | 登录 Mac 后自动打开 App，并恢复上次的开关状态 |
| **诊断和日志** | 打开诊断面板、查看日志、复制 API 地址 |

App 常驻菜单栏，不占用 Dock。底层代理能力由 [Copilot Proxy](https://github.com/Jer-y/copilot-proxy) 提供；本项目负责 macOS 桌面界面、启停管理和登录自启。

## 下载与安装

在 [Releases](https://github.com/Shirley7q/copilot-proxy-menubar/releases/latest) 下载最新版本：

- **DMG**：打开后，将 `Copilot Proxy.app` 拖入 `Applications`。
- **ZIP**：解压后，将 `Copilot Proxy.app` 移到“应用程序”文件夹。

发行包是 Universal App，包含 Intel 和 Apple Silicon 两种架构，要求 **macOS 13 或更新版本**。v1.0.0 的运行和手动操作验证在 Intel Mac 上完成；Apple Silicon 版本已交叉编译，尚未实机验证。

**首次打开：** 当前发行包使用临时签名，尚未经过 Apple 公证。如果 macOS 提示无法验证开发者，请在尝试打开后，进入“系统设置 → 隐私与安全性”选择“仍要打开”，再按系统提示完成确认。

## 开始使用

### 1. 准备运行环境

当前版本独立分发桌面 App，**安装包不包含 Node.js 或 Copilot Proxy 引擎**。请先准备：

- Node.js **22.19.0 或更新版本**。
- 已安装并完成登录的 `@jer-y/copilot-proxy`；本版本基于 **0.10.0** 验证。
- 可正常使用 GitHub Copilot 的账号。

如果已经可以通过 `copilot-proxy start` 使用代理，可以直接进入下一步。首次安装底层代理：

```bash
npm install -g @jer-y/copilot-proxy@0.10.0
copilot-proxy auth
```

账号登录和客户端接入的详细说明请参考 [Copilot Proxy 原项目文档](https://github.com/Jer-y/copilot-proxy#readme)。

### 2. 打开 App

双击 `Copilot Proxy.app`，在 Mac 右上角找到闪电圆环图标。

- 点击 **Enable**：启动代理。
- 点击 **Disable**：暂停代理。
- 打开“**登录 Mac 时自动启动**”：登录后恢复上次的开关状态。首次打开 App 默认注册登录项；如果系统要求允许，可点击菜单中的设置入口。

默认本地 API 地址：

```text
http://127.0.0.1:4399/v1
```

也可以使用菜单中的“复制 API 地址”。App 沿用底层代理已有的登录信息，无需重复输入账号。

### 3. 从终端切换到后台

如果代理已经在终端运行，App 会显示 **Enabled · 终端运行中**，首次打开不会打断现有连接。

点击“**切换到后台运行**”，等待显示 **Enabled** 后，即可关闭原终端。切换会短暂重启代理，正在进行的请求可能中断。

如果保持 Enable 状态，原终端代理退出后，App 也会自动启动后台代理。

## 开关与退出的行为

| 操作 | 结果 |
| --- | --- |
| Disable | 停止代理并记住关闭状态；下次登录不会自动启用代理 |
| 关闭登录自启 | 当前代理继续运行，下次登录不自动打开 App |
| 退出 App | 停止由 App 启动的代理；外部终端进程保持运行 |
| 再次打开 App | 恢复上次保存的 Enable / Disable 状态 |

菜单里的 Enable / Disable 是**代理运行开关**。App 通过 macOS 登录项启动，不需要另行执行 CLI 的 `copilot-proxy enable` 开机服务命令。请避免同时启用两套后台管理，以免争用端口。

## 诊断与日志

- “**打开诊断面板**”：检查本地代理状态。
- “**查看日志**”：打开 `~/Library/Logs/Copilot Proxy/proxy.log`。
- 日志保留当前和上一份，每份最多 2 MiB，仅当前用户可读写。
- 接管前的历史输出仍在原终端；App 日志从后台启动时开始记录。

端口被其他程序占用时，App 会显示提示，不会停止无法确认身份的进程。启动失败时可先查看日志，处理后再点击 Enable 重试。

## 当前版本范围

- 使用本机地址 `127.0.0.1` 和默认端口 `4399`。
- 使用底层代理的默认账号存储位置和默认启动行为。
- 自动查找常见 Node.js 安装位置，包括 Homebrew、`~/.local/bin`、Volta 和 nvm。
- 暂不提供自定义端口、额外启动参数、账号管理或引擎自动安装界面。
- 本项目独立维护和发布，不是 GitHub、Microsoft 或 Copilot Proxy 原作者提供的官方客户端。

## 从源码构建

需要 Apple Command Line Tools，可通过 `xcode-select --install` 安装。

```bash
git clone https://github.com/Shirley7q/copilot-proxy-menubar.git
cd copilot-proxy-menubar

# 构建当前 Mac 架构
bash build.sh

# 构建 Intel 与 Apple Silicon 通用 App
bash build.sh --universal

# 验证启停、接管、状态恢复和日志管理
bash test.sh

# 生成 DMG、ZIP 和 SHA-256 校验文件
bash release.sh
```

App 输出到 `build/Copilot Proxy.app`，发行文件输出到 `dist/`。测试使用空闲端口上的模拟服务，不停止正在使用的代理；运行测试也需要已安装 Node.js 和 Copilot Proxy。

## 卸载

先关闭“登录 Mac 时自动启动”，退出 App，再将 `Copilot Proxy.app` 移到废纸篓。底层 CLI 和原来的账号信息会继续保留。

## 致谢

感谢 [Jer-y](https://github.com/Jer-y) 创建并维护 [copilot-proxy](https://github.com/Jer-y/copilot-proxy)，提供本项目所依赖的本地代理能力。

原项目采用 [MIT License](https://github.com/Jer-y/copilot-proxy/blob/main/LICENSE)。本项目以独立 macOS 菜单栏 App 的形式构建桌面体验，底层能力的相关贡献与归属属于原项目及其贡献者。
