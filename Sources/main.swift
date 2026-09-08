import AppKit
import ServiceManagement

final class StatusHeader: NSView {
    private let name = NSTextField(labelWithString: "Copilot Proxy")
    private let status = NSTextField(labelWithString: "正在检查…")
    private let subtitle = NSTextField(labelWithString: "本地代理 · 127.0.0.1:4399")
    private let mark = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 84))
        mark.frame = NSRect(x: 18, y: 32, width: 32, height: 32)
        mark.image = NSImage(systemSymbolName: "bolt.horizontal.circle.fill", accessibilityDescription: "Copilot Proxy")
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        mark.contentTintColor = .systemMint
        name.frame = NSRect(x: 62, y: 51, width: 232, height: 20)
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        status.frame = NSRect(x: 62, y: 29, width: 232, height: 18)
        status.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.frame = NSRect(x: 18, y: 7, width: 278, height: 17)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        [mark, name, status, subtitle].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ controller: ProxyController) {
        status.stringValue = controller.state.title
        status.textColor = controller.state.active ? .systemGreen : .secondaryLabelColor
        mark.contentTintColor = controller.state.active ? .systemMint : .secondaryLabelColor
        subtitle.stringValue = "本地代理 · 127.0.0.1:\(controller.port)"
        toolTip = controller.detail
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controller: ProxyController?
    private let header = StatusHeader(frame: .zero)
    private var enableItem: NSMenuItem!
    private var disableItem: NSMenuItem!
    private var takeOverItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var loginApprovalItem: NSMenuItem!
    private var detailItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Finder normally enforces this, but guard direct executable launches too.
        let identifier = Bundle.main.bundleIdentifier ?? "local.shirley.CopilotProxyMenuBar"
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        do {
            controller = try ProxyController(runtime: Runtime.discover())
        } catch { showError(error.localizedDescription) }
        buildMenu()
        controller?.onChange = { [weak self] in self?.update() }
        controller?.monitor()
        // The requested login launch is registered once. Later user choices in
        // System Settings are respected, rather than silently re-enabling them.
        if !UserDefaults.standard.bool(forKey: "didConfigureLogin") {
            UserDefaults.standard.set(true, forKey: "didConfigureLogin")
            do { try SMAppService.mainApp.register() }
            catch { controller?.log.note("Login item registration failed: \(error.localizedDescription)") }
        }
        update()
    }

    private func item(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol = symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.setAccessibilityLabel("Copilot Proxy")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let title = NSMenuItem()
        title.view = header
        menu.addItem(title)
        menu.addItem(.separator())
        enableItem = item("Enable", #selector(enableProxy), symbol: "power")
        disableItem = item("Disable", #selector(disableProxy), symbol: "pause.circle")
        menu.addItem(enableItem)
        menu.addItem(disableItem)
        takeOverItem = item("切换到后台运行", #selector(takeOver), symbol: "arrow.triangle.2.circlepath")
        menu.addItem(takeOverItem)
        detailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        menu.addItem(detailItem)
        menu.addItem(.separator())
        loginItem = item("登录 Mac 时自动启动", #selector(toggleLogin), symbol: "sunrise")
        menu.addItem(loginItem)
        loginApprovalItem = item("在系统设置中允许自动启动…", #selector(openLoginSettings), symbol: "gearshape")
        menu.addItem(loginApprovalItem)
        menu.addItem(.separator())
        menu.addItem(item("复制 API 地址", #selector(copyEndpoint), symbol: "doc.on.doc"))
        menu.addItem(item("打开诊断面板", #selector(openDashboard), symbol: "gauge.with.dots.needle.50percent"))
        menu.addItem(item("查看日志", #selector(openLogs), symbol: "doc.text.magnifyingglass"))
        menu.addItem(item("使用说明", #selector(showHelp), symbol: "questionmark.circle"))
        menu.addItem(.separator())
        quitItem = item("退出 Copilot Proxy", #selector(quit), symbol: "rectangle.portrait.and.arrow.right")
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        update()
        Task { await controller?.refresh() }
    }

    private func update() {
        guard statusItem != nil else { return }
        let state = controller?.state ?? .failed("找不到运行环境")
        if let controller = controller { header.update(controller) }
        let symbol: String
        switch state {
        case .running, .external: symbol = "bolt.horizontal.circle.fill"
        case .starting, .stopping: symbol = "arrow.triangle.2.circlepath"
        case .failed: symbol = "exclamationmark.circle"
        case .stopped: symbol = "bolt.horizontal.circle"
        }
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "Copilot Proxy — \(state.title)")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "Copilot Proxy · \(state.title)\n\(controller?.detail ?? "")"
        enableItem.isEnabled = controller != nil && !state.active && !state.busy
        enableItem.state = state.active ? .on : .off
        disableItem.isEnabled = controller != nil && !state.busy && state != .stopped
        disableItem.state = state == .stopped ? .on : .off
        takeOverItem.isHidden = state != .external
        takeOverItem.toolTip = "将短暂重启代理，然后由菜单栏应用管理。"
        detailItem.title = controller?.detail ?? "请安装 copilot-proxy 和 Node.js"
        if detailItem.title.count > 34 {
            detailItem.toolTip = detailItem.title
            detailItem.title = String(detailItem.title.prefix(32)) + "…"
        }
        let login = SMAppService.mainApp.status
        loginItem.state = login == .enabled ? .on : login == .requiresApproval ? .mixed : .off
        loginApprovalItem.isHidden = login != .requiresApproval
        quitItem.isEnabled = !state.busy
    }

    @objc private func enableProxy() { Task { await controller?.enable() } }

    @objc private func disableProxy() {
        Task {
            do { try await controller?.disable() }
            catch { showError(error.localizedDescription) }
        }
    }

    @objc private func takeOver() {
        Task {
            do { try await controller?.takeOver() }
            catch { showError(error.localizedDescription) }
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch { showError("无法更改自动启动：\(error.localizedDescription)") }
        update()
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    @objc private func copyEndpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(controller?.endpoint ?? "http://127.0.0.1:4399")/v1", forType: .string)
    }

    @objc private func openDashboard() {
        let endpoint = "\(controller?.endpoint ?? "http://127.0.0.1:4399")/diagnostics"
        var url = URLComponents(string: "https://jer-y.github.io/copilot-proxy")!
        url.queryItems = [URLQueryItem(name: "endpoint", value: endpoint)]
        if let url = url.url { NSWorkspace.shared.open(url) }
    }

    @objc private func openLogs() {
        if let url = controller?.log.url { NSWorkspace.shared.open(url) }
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Copilot Proxy"
        alert.informativeText = "Enable 启动代理，Disable 暂停代理。\n\n启用“登录 Mac 时自动启动”后，应用会在登录时恢复上次的 Enable / Disable 状态。\n\n如果显示“终端运行中”，点“切换到后台运行”后即可关掉原终端；切换会短暂重启代理。\n\n退出应用会停止由应用启动的代理。再次打开会恢复上次状态。\n\nAPI 地址：http://127.0.0.1:4399/v1\n继续使用已安装的 copilot-proxy、Node.js 和已有账号。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Copilot Proxy"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            await controller?.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

if CommandLine.arguments.contains("--login-status") {
    let status: String
    switch SMAppService.mainApp.status {
    case .enabled: status = "enabled"
    case .notRegistered: status = "notRegistered"
    case .requiresApproval: status = "requiresApproval"
    case .notFound: status = "notFound"
    @unknown default: status = "unknown"
    }
    print(status)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
