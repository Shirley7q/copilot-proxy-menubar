import Foundation
import Darwin

struct ProxyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Runtime {
    let node: URL
    let cli: URL

    static func discover() throws -> Runtime {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = ["/usr/local/bin", "/opt/homebrew/bin", "\(home)/.local/bin", "\(home)/.volta/bin"]
        let nvm = URL(fileURLWithPath: "\(home)/.nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
            directories += versions.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }.map { $0.appendingPathComponent("bin").path }
        }
        directories += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard let cli = directories.map({ URL(fileURLWithPath: $0).appendingPathComponent("copilot-proxy") }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ProxyError(message: "找不到 copilot-proxy。请先安装它，再重新打开应用。")
        }
        let nodeDirs = [cli.deletingLastPathComponent().path] + directories
        guard let node = nodeDirs.map({ URL(fileURLWithPath: $0).appendingPathComponent("node") }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ProxyError(message: "找不到 Node.js。请先安装 Node.js，再重新打开应用。")
        }
        return Runtime(node: node.resolvingSymlinksInPath(), cli: cli.resolvingSymlinksInPath())
    }

    var environment: [String: String] {
        // Launch only with the OS environment needed by this CLI. Authentication
        // stays in the CLI's existing account store, never in the app preferences.
        var env: [String: String] = [:]
        for key in ["TMPDIR", "LANG", "LC_ALL", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING"] {
            env[key] = ProcessInfo.processInfo.environment[key]
        }
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["USER"] = NSUserName()
        env["LOGNAME"] = NSUserName()
        env["PATH"] = "\(node.deletingLastPathComponent().path):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["NO_COLOR"] = "1"
        return env
    }
}

final class RollingLog {
    let url: URL
    private let lock = NSLock()
    private let maxSize = 2 * 1024 * 1024
    private var handle: FileHandle?

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try open()
    }

    private func open() throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw ProxyError(message: "无法创建日志文件。")
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        do {
            if Int(try handle?.offset() ?? 0) + data.count > maxSize {
                try handle?.close()
                let old = url.appendingPathExtension("1")
                if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
                try FileManager.default.moveItem(at: url, to: old)
                try open()
            }
            try handle?.write(contentsOf: data.suffix(maxSize))
        } catch {
            NSLog("Copilot Proxy: log write failed: %@", error.localizedDescription)
        }
    }

    func note(_ message: String) {
        append(Data("\n[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n".utf8))
    }
}

enum ProcessInspector {
    static func output(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
    }

    static func listeners(port: Int) -> [pid_t] {
        output("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"])
            .split(separator: "\n").compactMap { $0.first == "p" ? Int32($0.dropFirst()) : nil }
    }

    static func arguments(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var length = 0
        guard sysctl(&mib, 3, nil, &length, nil, 0) == 0, length > 4 else { return [] }
        var bytes = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 3, &bytes, &length, nil, 0) == 0 else { return [] }
        let count = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        guard count > 0, count < 4096 else { return [] }
        var cursor = MemoryLayout<Int32>.size
        while cursor < length && bytes[cursor] != 0 { cursor += 1 }
        while cursor < length && bytes[cursor] == 0 { cursor += 1 }
        var result: [String] = []
        for _ in 0..<count {
            let start = cursor
            while cursor < length && bytes[cursor] != 0 { cursor += 1 }
            guard cursor < length else { return [] }
            result.append(String(decoding: bytes[start..<cursor], as: UTF8.self))
            cursor += 1
        }
        return result
    }

    static func isProxy(pid: pid_t, runtime: Runtime) -> Bool {
        let uid = output("/bin/ps", ["-p", String(pid), "-o", "uid="]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard uid == String(getuid()) else { return false }
        let args = arguments(pid: pid)
        guard args.count >= 3, args[2] == "start" else { return false }
        let cli = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath()
        return cli == runtime.cli && URL(fileURLWithPath: args[0]).lastPathComponent == "node"
    }
}

@MainActor
final class ProxyController {
    enum State: Equatable {
        case stopped, starting, running, external, stopping, failed(String)
        var title: String {
            switch self {
            case .stopped: return "Disabled"
            case .starting: return "正在启动…"
            case .running: return "Enabled"
            case .external: return "Enabled · 终端运行中"
            case .stopping: return "正在停止…"
            case .failed: return "需要处理"
            }
        }
        var busy: Bool { self == .starting || self == .stopping }
        var active: Bool { self == .running || self == .external }
    }

    let port: Int
    let runtime: Runtime
    let log: RollingLog
    let defaults: UserDefaults
    private(set) var state: State = .stopped { didSet { if oldValue != state { onChange?() } } }
    private(set) var enabled: Bool
    var onChange: (() -> Void)?
    private var process: Process?
    private var outputPipe: Pipe?
    private var startedAt: Date?
    private var checking = false
    private var quitting = false
    private var errorLatched = false
    private var restartTimes: [Date] = []
    private var timer: Timer?
    private var generation = 0
    private let session: URLSession

    var endpoint: String { "http://127.0.0.1:\(port)" }
    var detail: String {
        switch state {
        case .running: return "后台运行 · 可关闭终端"
        case .external: return "选择“切换到后台运行”即可关闭终端"
        case .stopped: return "代理已暂停"
        case .starting: return "正在连接 GitHub Copilot"
        case .stopping: return "正在关闭代理连接"
        case .failed(let message): return message
        }
    }

    init(runtime: Runtime, port: Int = 4399, defaults: UserDefaults = .standard, logURL: URL? = nil) throws {
        self.runtime = runtime
        self.port = port
        self.defaults = defaults
        self.enabled = defaults.object(forKey: "proxyEnabled") as? Bool ?? true
        let url = logURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Copilot Proxy/proxy.log")
        self.log = try RollingLog(url: url)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config)
    }

    func monitor() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !checking, !quitting, state != .stopping else { return }
        checking = true
        defer { checking = false }
        let snapshot = generation
        let port = self.port
        let pids = await Task.detached { ProcessInspector.listeners(port: port) }.value
        guard snapshot == generation, !quitting else { return }
        if !pids.isEmpty {
            let runtime = self.runtime
            let verified = await Task.detached { pids.allSatisfy { ProcessInspector.isProxy(pid: $0, runtime: runtime) } }.value
            guard snapshot == generation, !quitting else { return }
            guard verified else {
                state = .failed("端口 \(port) 被其他程序占用，请先释放端口。")
                return
            }
            do {
                let (data, response) = try await session.data(from: URL(string: "\(endpoint)/readyz")!)
                guard snapshot == generation, !quitting else { return }
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                if (response as? HTTPURLResponse)?.statusCode == 200 && body?["status"] as? String == "ready" {
                    state = process?.isRunning == true ? .running : .external
                } else {
                    state = .failed("代理尚未就绪，请查看诊断面板或日志。")
                }
            } catch {
                guard snapshot == generation, !quitting else { return }
                state = .failed("代理暂时无响应，请查看日志或重试。")
            }
            return
        }
        if process?.isRunning == true {
            if let start = startedAt, Date().timeIntervalSince(start) > 90 {
                state = .failed("启动超过 90 秒，请查看日志；可 Disable 后重试。")
            } else { state = .starting }
        } else if enabled && !errorLatched {
            start()
        } else if !errorLatched { state = .stopped }
    }

    func enable() async {
        enabled = true
        defaults.set(true, forKey: "proxyEnabled")
        errorLatched = false
        restartTimes.removeAll()
        await refresh()
    }

    private func start() {
        guard process?.isRunning != true, !quitting else { return }
        generation += 1
        state = .starting
        startedAt = Date()
        let child = Process()
        let pipe = Pipe()
        child.executableURL = runtime.node
        child.arguments = [runtime.cli.path, "start", "--host", "127.0.0.1", "--port", String(port)]
        child.environment = runtime.environment
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = pipe
        child.standardError = pipe
        let log = self.log
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { log.append(data) }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in self?.didExit(child) }
        }
        process = child
        outputPipe = pipe
        do {
            log.note("Starting copilot-proxy on 127.0.0.1:\(port)")
            try child.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            outputPipe = nil
            errorLatched = true
            state = .failed("启动失败：\(error.localizedDescription)")
        }
    }

    private func didExit(_ child: Process) {
        guard process === child else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        log.note("Proxy exited with status \(child.terminationStatus)")
        guard !quitting, state != .stopping, enabled else { return }
        let now = Date()
        restartTimes = restartTimes.filter { now.timeIntervalSince($0) < 60 }
        restartTimes.append(now)
        if restartTimes.count >= 3 || (child.terminationStatus != 0 && now.timeIntervalSince(startedAt ?? now) < 10) {
            errorLatched = true
            state = .failed("代理意外退出。请查看日志，然后点击 Enable 重试。")
        } else {
            state = .starting
        }
    }

    func disable() async throws {
        enabled = false
        defaults.set(false, forKey: "proxyEnabled")
        errorLatched = false
        generation += 1
        state = .stopping
        do {
            try await stopAllVerified()
            state = .stopped
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func takeOver() async throws {
        guard state == .external else { return }
        generation += 1
        state = .stopping
        do {
            try await stopAllVerified()
            enabled = true
            defaults.set(true, forKey: "proxyEnabled")
            errorLatched = false
            restartTimes.removeAll()
            start()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func stopAllVerified() async throws {
        let port = self.port
        let runtime = self.runtime
        let pids = await Task.detached { ProcessInspector.listeners(port: port) }.value
        let owned = process?.isRunning == true ? process?.processIdentifier : nil
        let targets = Set(pids + (owned.map { [$0] } ?? []))
        // Recheck exact executable arguments and ownership immediately before each signal.
        // Refuse unrelated listeners; never use killall/pkill or a substring match.
        for pid in targets {
            guard ProcessInspector.isProxy(pid: pid, runtime: runtime) else {
                throw ProxyError(message: "无法确认端口 \(port) 上的进程身份，未停止该程序。")
            }
            guard kill(pid, SIGTERM) == 0 || errno == ESRCH else {
                throw ProxyError(message: "无法停止代理进程，请在原终端中按 Control-C。")
            }
        }
        for _ in 0..<60 {
            let remaining = await Task.detached { ProcessInspector.listeners(port: port) }.value
            if remaining.isEmpty && process?.isRunning != true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProxyError(message: "代理仍在退出，请稍后重试。如果由其他后台服务启动，请先关闭那个服务。")
    }

    func shutdown() async {
        quitting = true
        generation += 1
        timer?.invalidate()
        // Quit only stops the child owned by this app; external terminal sessions stay intact.
        if let child = process, child.isRunning {
            child.terminate()
            for _ in 0..<40 {
                if !child.isRunning { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if child.isRunning && ProcessInspector.isProxy(pid: child.processIdentifier, runtime: runtime) {
                kill(child.processIdentifier, SIGKILL)
            }
        }
    }
}
