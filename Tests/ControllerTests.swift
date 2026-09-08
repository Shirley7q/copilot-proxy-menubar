import Foundation
import Darwin

@main
struct ControllerTests {
    @MainActor
    static func main() async {
        do { try await run(); print("PASS: all lifecycle checks"); exit(0) }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ProxyError(message: message) }
    }

    @MainActor
    static func waitFor(_ controller: ProxyController, _ expected: ProxyController.State) async throws {
        for _ in 0..<50 {
            await controller.refresh()
            if controller.state == expected { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProxyError(message: "Expected \(expected), got \(controller.state)")
    }

    @MainActor
    static func run() async throws {
        let installed = try Runtime.discover()
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        let runtime = Runtime(node: installed.node, cli: fixture)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-menubar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let suite = "local.shirley.CopilotProxyMenuBar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "proxyEnabled")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temporary)
        }
        let port = (45439..<45499).first { ProcessInspector.listeners(port: $0).isEmpty }!
        let controller = try ProxyController(runtime: runtime, port: port, defaults: defaults, logURL: temporary.appendingPathComponent("proxy.log"))
        await controller.refresh()
        try require(controller.state == .stopped, "Disabled preference must not start the proxy")
        await controller.enable()
        try await waitFor(controller, .running)
        let ownedPID = ProcessInspector.listeners(port: port).first!
        try require(ProcessInspector.isProxy(pid: ownedPID, runtime: runtime), "Must recognize the exact child argv")
        try await controller.disable()
        try require(ProcessInspector.listeners(port: port).isEmpty, "Disable must release the port")
        try require(!defaults.bool(forKey: "proxyEnabled"), "Disable must persist")
        print("PASS: Enable, readiness, Disable, saved state, port cleanup")

        let external = Process()
        external.executableURL = runtime.node
        external.arguments = [runtime.cli.path, "start", "--port", String(port)]
        external.standardOutput = FileHandle.nullDevice
        external.standardError = FileHandle.nullDevice
        try external.run()
        defer { if external.isRunning { external.terminate() } }
        try await waitFor(controller, .external)
        try await controller.takeOver()
        try await waitFor(controller, .running)
        try require(!external.isRunning, "Takeover must stop the original process")
        try require(ProcessInspector.listeners(port: port).count == 1, "Takeover must create one listener")
        await controller.shutdown()
        try require(ProcessInspector.listeners(port: port).isEmpty, "Quit must clean up the owned child")
        try require(defaults.bool(forKey: "proxyEnabled"), "Quit must preserve enabled preference")
        print("PASS: external detection, background takeover, quit cleanup")

        let restored = try ProxyController(runtime: runtime, port: port, defaults: defaults, logURL: temporary.appendingPathComponent("restored.log"))
        await restored.refresh()
        try await waitFor(restored, .running)
        try await restored.disable()
        print("PASS: enabled state restored on next launch")

        let unrelatedScript = temporary.appendingPathComponent("unrelated.cjs")
        try FileManager.default.copyItem(at: fixture, to: unrelatedScript)
        let unrelated = Process()
        unrelated.executableURL = runtime.node
        unrelated.arguments = [unrelatedScript.path, "start", "--port", String(port)]
        unrelated.standardOutput = FileHandle.nullDevice
        unrelated.standardError = FileHandle.nullDevice
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }
        for _ in 0..<30 {
            if !ProcessInspector.listeners(port: port).isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await restored.refresh()
        guard case .failed = restored.state else { throw ProxyError(message: "Unrelated port collision must be reported") }
        var refused = false
        do { try await restored.disable() } catch { refused = true }
        try require(refused && unrelated.isRunning, "Never terminate an unrelated process on the port")
        unrelated.terminate()
        unrelated.waitUntilExit()
        await restored.shutdown()
        print("PASS: refuses to stop an unrelated listener")

        let badScript = temporary.appendingPathComponent("failing.cjs")
        try Data("process.exit(1);\n".utf8).write(to: badScript)
        defaults.set(false, forKey: "proxyEnabled")
        let failing = try ProxyController(runtime: Runtime(node: runtime.node, cli: badScript), port: port, defaults: defaults, logURL: temporary.appendingPathComponent("failing.log"))
        await failing.enable()
        try await Task.sleep(nanoseconds: 500_000_000)
        await failing.refresh()
        guard case .failed = failing.state else { throw ProxyError(message: "Early startup failure must surface instead of endlessly restarting") }
        await failing.shutdown()
        print("PASS: startup failure is visible and does not loop")

        let log = try RollingLog(url: temporary.appendingPathComponent("bounded.log"))
        log.append(Data(repeating: 65, count: 1_500_000))
        log.append(Data(repeating: 66, count: 1_500_000))
        let attributes = try FileManager.default.attributesOfItem(atPath: log.url.path)
        try require((attributes[.size] as? Int ?? 0) <= 2 * 1024 * 1024, "Log must remain bounded")
        try require((attributes[.posixPermissions] as? Int ?? 0) == 0o600, "Log must be owner-only")
        try require(FileManager.default.fileExists(atPath: log.url.appendingPathExtension("1").path), "Log must rotate")
        print("PASS: bounded, owner-only logs")

        // The real active proxy is inspected only; it is never stopped by tests.
        let live = ProcessInspector.listeners(port: 4399)
        if !live.isEmpty {
            try require(live.allSatisfy { ProcessInspector.isProxy(pid: $0, runtime: installed) }, "Installed CLI must be recognized")
            print("PASS: recognizes existing production CLI without changing it")
        }
    }
}
