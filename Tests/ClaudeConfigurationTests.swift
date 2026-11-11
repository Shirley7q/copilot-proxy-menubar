import Foundation

enum ClaudeConfigurationTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ProxyError(message: message) }
    }

    static func run(fixture: URL) throws {
        let data = try Data(contentsOf: fixture.deletingLastPathComponent().appendingPathComponent("claude-diagnostics.json"))
        let models = try ClaudeConfiguration.models(from: data)
        try require(models.map(\.id) == ["claude-haiku-4.5", "claude-sonnet-4.6"], "Only unique Claude models with direct Messages support may be selected")
        let primary = models[1]
        let small = models[0]
        try require(primary.clientModel == "claude-sonnet-4-6[1m]", "Respect advertised 1M context and Claude's model spelling")
        try require(small.clientModel == "claude-haiku-4-5", "Do not enable unadvertised 1M context")
        for invalid in ["{}", "not json", "{\"models\":[]}", "{\"models\":[{\"id\":\"claude-unknown\"}]}"] {
            var rejected = false
            do { _ = try ClaudeConfiguration.models(from: Data(invalid.utf8)) }
            catch { rejected = true }
            try require(rejected, "Reject unavailable or malformed catalogs")
        }
        print("PASS: Claude model eligibility, deduplication, model selectors, invalid catalogs")

        for shell in ["/bin/bash", "/bin/zsh"] {
            let command = try ClaudeConfiguration.launchCommand(port: 45439, model: primary, smallModel: small)
            let args = try arguments(for: command, shell: shell)
            try require(args.count == 4 && args[0] == "--model" && args[1] == primary.clientModel && args[2] == "--settings", "Launch must explicitly select the chosen model and a session settings overlay")
            let settings = try JSONSerialization.jsonObject(with: Data(args[3].utf8)) as! [String: Any]
            let env = settings["env"] as! [String: String]
            try require(env["ANTHROPIC_BASE_URL"] == "http://127.0.0.1:45439", "Anthropic base URL must not include /v1")
            try require(ProxyEndpoints(port: 45439).openAI == "http://127.0.0.1:45439/v1", "Retain the Codex/OpenAI /v1 endpoint")
            try require(env["ANTHROPIC_AUTH_TOKEN"] == "dummy" && env["ANTHROPIC_API_KEY"] == "", "Use local placeholder auth instead of an inherited API key")
            try require(env["ANTHROPIC_MODEL"] == primary.clientModel && env["ANTHROPIC_DEFAULT_OPUS_MODEL"] == primary.clientModel && env["ANTHROPIC_DEFAULT_SONNET_MODEL"] == primary.clientModel, "Pin primary aliases to an available model")
            try require(env["ANTHROPIC_SMALL_FAST_MODEL"] == small.clientModel && env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == small.clientModel, "Pin background calls to the selected small model")

            // Treat even shell metacharacters in a server-supplied ID as data.
            let unusual = ClaudeModel(id: "claude-test'\";$(printf INJECTED)`printf INJECTED`\n", displayName: nil, contextWindow: nil, routes: .init(anthropicMessages: .init(mode: "direct")))
            let quoted = try ClaudeConfiguration.launchCommand(port: 45439, model: unusual, smallModel: small)
            let unusualArgs = try arguments(for: quoted, shell: shell)
            try require(unusualArgs.count == 4 && unusualArgs[1] == unusual.id, "Shell metacharacters must not be evaluated")
            let unusualSettings = try JSONSerialization.jsonObject(with: Data(unusualArgs[3].utf8)) as! [String: Any]
            try require((unusualSettings["env"] as? [String: String])?["ANTHROPIC_MODEL"] == unusual.id, "Settings must survive shell and JSON decoding intact")
        }
        print("PASS: Claude launch arguments round-trip in Bash and Zsh; Codex endpoint preserved")
    }

    private static func arguments(for command: String, shell: String) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        // A stub captures argv. No installed Claude client or model request is used.
        process.arguments = ["-f", "-c", "claude() { /usr/bin/printf '%s\\0' \"$@\"; }; " + command]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try require(process.terminationStatus == 0, "Generated launch command must parse in \(shell)")
        return data.split(separator: 0, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
    }
}
