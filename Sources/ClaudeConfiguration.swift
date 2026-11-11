import Foundation

struct ProxyEndpoints {
    let port: Int
    var anthropic: String { "http://127.0.0.1:\(port)" }
    var openAI: String { "\(anthropic)/v1" }
}

struct ClaudeModel: Decodable, Equatable {
    struct Route: Decodable, Equatable {
        let mode: String
    }
    struct Routes: Decodable, Equatable {
        let anthropicMessages: Route?
    }

    let id: String
    let displayName: String?
    let contextWindow: Int?
    let routes: Routes?

    var supportsClaudeCode: Bool {
        id.hasPrefix("claude-") && routes?.anthropicMessages?.mode == "direct"
    }

    var clientModel: String {
        // Match copilot-proxy's Claude selector format; the proxy normalizes it
        // back to the catalog ID when forwarding Messages requests.
        let name = id.replacingOccurrences(
            of: "^(claude-(?:sonnet|opus|haiku)-[0-9]+)\\.([0-9]+)$",
            with: "$1-$2", options: .regularExpression)
        return (contextWindow ?? 0) >= 1_000_000 ? "\(name)[1m]" : name
    }

    var title: String { "\(displayName ?? id) · \(id)" }
}

enum ClaudeConfiguration {
    private struct Diagnostics: Decodable {
        let models: [ClaudeModel]
    }

    static func models(from data: Data) throws -> [ClaudeModel] {
        let diagnostics: Diagnostics
        do { diagnostics = try JSONDecoder().decode(Diagnostics.self, from: data) }
        catch { throw ProxyError(message: "无法读取代理的模型目录，请检查 Copilot Proxy 版本或诊断面板。") }
        var seen = Set<String>()
        let models = diagnostics.models.filter { $0.supportsClaudeCode && seen.insert($0.id).inserted }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        guard !models.isEmpty else {
            throw ProxyError(message: "当前账号没有可直连 Messages 接口的 Claude 模型，请检查 Copilot 模型权限或诊断面板。")
        }
        return models
    }

    static func loadModels(port: Int) async throws -> [ClaudeModel] {
        let config = URLSessionConfiguration.ephemeral
        // /diagnostics can spend up to 8 seconds retrieving usage information.
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "\(ProxyEndpoints(port: port).anthropic)/diagnostics")!
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(from: url) }
        catch { throw ProxyError(message: "无法连接代理，请先点击 Enable，等待显示 Enabled 后重试。") }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProxyError(message: "代理未能返回模型目录，请查看诊断面板或日志。")
        }
        return try models(from: data)
    }

    static func launchCommand(port: Int, model: ClaudeModel, smallModel: ClaudeModel) throws -> String {
        guard model.supportsClaudeCode, smallModel.supportsClaudeCode else {
            throw ProxyError(message: "请选择支持 Messages 接口的 Claude 模型。")
        }
        let env = [
            "ANTHROPIC_BASE_URL": ProxyEndpoints(port: port).anthropic,
            "ANTHROPIC_AUTH_TOKEN": "dummy",
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_MODEL": model.clientModel,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": model.clientModel,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": model.clientModel,
            "ANTHROPIC_SMALL_FAST_MODEL": smallModel.clientModel,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": smallModel.clientModel,
            "CLAUDE_CODE_USE_BEDROCK": "0",
            "CLAUDE_CODE_USE_VERTEX": "0",
            "CLAUDE_CODE_USE_FOUNDRY": "0"
        ]
        let data = try JSONSerialization.data(withJSONObject: ["env": env], options: [.sortedKeys, .withoutEscapingSlashes])
        let settings = String(decoding: data, as: UTF8.self)
        return "claude --model \(shellQuote(model.clientModel)) --settings \(shellQuote(settings))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
