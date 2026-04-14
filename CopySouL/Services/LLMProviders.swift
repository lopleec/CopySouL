import Foundation

protocol LLMProvider {
    var kind: ProviderKind { get }

    func makeRequest(
        configuration: LLMConfiguration,
        apiKey: String?,
        messages: [LLMMessage],
        tools: [LLMTool],
        preferVision: Bool
    ) throws -> URLRequest

    func decodeResponse(_ data: Data) throws -> LLMResult
}

struct LLMProviderFactory {
    static func provider(for kind: ProviderKind) -> LLMProvider {
        switch kind {
        case .openAICompatible:
            return OpenAICompatibleProvider()
        case .claude:
            return ClaudeProvider()
        case .gemini:
            return GeminiProvider()
        case .ollamaCompatible:
            return OllamaCompatibleProvider()
        }
    }
}

struct LLMClient {
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func complete(configuration: LLMConfiguration, messages: [LLMMessage], tools: [LLMTool] = [], preferVision: Bool = false) async throws -> LLMResult {
        let apiKey = try keychain.apiKey(account: configuration.apiKeyAccount)
        let provider = LLMProviderFactory.provider(for: configuration.provider)
        let request = try provider.makeRequest(
            configuration: configuration,
            apiKey: apiKey,
            messages: messages,
            tools: tools,
            preferVision: preferVision
        )
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "CopySouL.LLM", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try provider.decodeResponse(data)
    }
}

struct OpenAICompatibleProvider: LLMProvider {
    let kind: ProviderKind = .openAICompatible

    func makeRequest(configuration: LLMConfiguration, apiKey: String?, messages: [LLMMessage], tools: [LLMTool], preferVision: Bool) throws -> URLRequest {
        guard let apiKey, !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let model = preferVision ? configuration.visionModel : configuration.chatModel
        let url = configuration.baseURL.appendingPathIfMissing("v1/chat/completions")
        var body: [String: Any] = [
            "model": model,
            "messages": try messages.map(openAIMessage)
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters.foundationValue
                    ]
                ]
            }
            body["tool_choice"] = "auto"
        }
        return try jsonRequest(url: url, body: body, headers: ["Authorization": "Bearer \(apiKey)"])
    }

    func decodeResponse(_ data: Data) throws -> LLMResult {
        let root = try jsonObject(data)
        guard let choices = root["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] else {
            throw LLMError.responseFormat
        }
        let text = message["content"] as? String ?? ""
        let toolCalls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call -> LLMToolCall? in
            guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
            return LLMToolCall(
                id: (call["id"] as? String) ?? UUID().uuidString,
                name: name,
                argumentsJSON: (function["arguments"] as? String) ?? "{}"
            )
        }
        return LLMResult(text: text, toolCalls: toolCalls)
    }

    private func openAIMessage(_ message: LLMMessage) throws -> [String: Any] {
        var result: [String: Any] = ["role": message.role.openAIRole]
        if message.attachments.isEmpty {
            result["content"] = message.text
        } else {
            var content: [[String: Any]] = [["type": "text", "text": message.text]]
            for attachment in message.attachments {
                let dataURL = try attachment.dataURL()
                content.append(["type": "image_url", "image_url": ["url": dataURL]])
            }
            result["content"] = content
        }
        return result
    }
}

struct ClaudeProvider: LLMProvider {
    let kind: ProviderKind = .claude

    func makeRequest(configuration: LLMConfiguration, apiKey: String?, messages: [LLMMessage], tools: [LLMTool], preferVision: Bool) throws -> URLRequest {
        guard let apiKey, !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let model = preferVision ? configuration.visionModel : configuration.chatModel
        let system = messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        let conversational = try messages.filter { $0.role != .system }.map(claudeMessage)
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": conversational
        ]
        if !system.isEmpty {
            body["system"] = system
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.parameters.foundationValue
                ]
            }
        }
        return try jsonRequest(
            url: configuration.baseURL.appendingPathIfMissing("v1/messages"),
            body: body,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01"
            ]
        )
    }

    func decodeResponse(_ data: Data) throws -> LLMResult {
        let root = try jsonObject(data)
        guard let content = root["content"] as? [[String: Any]] else { throw LLMError.responseFormat }
        let text = content.compactMap { part -> String? in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }.joined(separator: "\n")
        let toolCalls = content.compactMap { part -> LLMToolCall? in
            guard part["type"] as? String == "tool_use", let name = part["name"] as? String else { return nil }
            let input = part["input"] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8)
            return LLMToolCall(id: (part["id"] as? String) ?? UUID().uuidString, name: name, argumentsJSON: String(data: data, encoding: .utf8) ?? "{}")
        }
        return LLMResult(text: text, toolCalls: toolCalls)
    }

    private func claudeMessage(_ message: LLMMessage) throws -> [String: Any] {
        var content: [[String: Any]] = []
        if !message.text.isEmpty {
            content.append(["type": "text", "text": message.text])
        }
        for attachment in message.attachments {
            let data = try attachment.base64ImageData()
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": attachment.mimeType,
                    "data": data
                ]
            ])
        }
        return ["role": message.role == .assistant ? "assistant" : "user", "content": content]
    }
}

struct GeminiProvider: LLMProvider {
    let kind: ProviderKind = .gemini

    func makeRequest(configuration: LLMConfiguration, apiKey: String?, messages: [LLMMessage], tools: [LLMTool], preferVision: Bool) throws -> URLRequest {
        guard let apiKey, !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let model = preferVision ? configuration.visionModel : configuration.chatModel
        let url = try geminiURL(baseURL: configuration.baseURL, model: model, apiKey: apiKey)
        var body: [String: Any] = [
            "contents": try messages.map(geminiContent)
        ]
        if !tools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters.foundationValue
                    ]
                }
            ]]
        }
        return try jsonRequest(url: url, body: body)
    }

    func decodeResponse(_ data: Data) throws -> LLMResult {
        let root = try jsonObject(data)
        guard
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw LLMError.responseFormat
        }
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let toolCalls = parts.compactMap { part -> LLMToolCall? in
            guard let functionCall = part["functionCall"] as? [String: Any], let name = functionCall["name"] as? String else { return nil }
            let args = functionCall["args"] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
            return LLMToolCall(id: UUID().uuidString, name: name, argumentsJSON: String(data: data, encoding: .utf8) ?? "{}")
        }
        return LLMResult(text: text, toolCalls: toolCalls)
    }

    private func geminiContent(_ message: LLMMessage) throws -> [String: Any] {
        var parts: [[String: Any]] = []
        if !message.text.isEmpty {
            parts.append(["text": message.role == .system ? "System: \(message.text)" : message.text])
        }
        for attachment in message.attachments {
            parts.append([
                "inlineData": [
                    "mimeType": attachment.mimeType,
                    "data": try attachment.base64ImageData()
                ]
            ])
        }
        return ["role": message.role == .assistant ? "model" : "user", "parts": parts]
    }

    private func geminiURL(baseURL: URL, model: String, apiKey: String) throws -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(base)/v1beta/models/\(model):generateContent") else {
            throw LLMError.invalidBaseURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw LLMError.invalidBaseURL }
        return url
    }
}

struct OllamaCompatibleProvider: LLMProvider {
    let kind: ProviderKind = .ollamaCompatible

    func makeRequest(configuration: LLMConfiguration, apiKey: String?, messages: [LLMMessage], tools: [LLMTool], preferVision: Bool) throws -> URLRequest {
        let model = preferVision ? configuration.visionModel : configuration.chatModel
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": try messages.map(ollamaMessage)
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters.foundationValue
                    ]
                ]
            }
        }
        var headers = [String: String]()
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return try jsonRequest(url: configuration.baseURL.appendingPathIfMissing("api/chat"), body: body, headers: headers)
    }

    func decodeResponse(_ data: Data) throws -> LLMResult {
        let root = try jsonObject(data)
        guard let message = root["message"] as? [String: Any] else { throw LLMError.responseFormat }
        let text = message["content"] as? String ?? ""
        let toolCalls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call -> LLMToolCall? in
            guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
            let arguments = function["arguments"] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
            return LLMToolCall(id: UUID().uuidString, name: name, argumentsJSON: String(data: data, encoding: .utf8) ?? "{}")
        }
        return LLMResult(text: text, toolCalls: toolCalls)
    }

    private func ollamaMessage(_ message: LLMMessage) throws -> [String: Any] {
        var result: [String: Any] = [
            "role": message.role.openAIRole,
            "content": message.text
        ]
        if !message.attachments.isEmpty {
            result["images"] = try message.attachments.map { try $0.base64ImageData() }
        }
        return result
    }
}

private func jsonRequest(url: URL, body: [String: Any], headers: [String: String] = [:]) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    return request
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw LLMError.responseFormat
    }
    return object
}

private extension URL {
    func appendingPathIfMissing(_ path: String) -> URL {
        let base = absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix(path) {
            return self
        }
        return URL(string: "\(base)/\(path)") ?? appendingPathComponent(path)
    }
}

private extension ChatRole {
    var openAIRole: String {
        switch self {
        case .system:
            return "system"
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .tool:
            return "tool"
        }
    }
}

private extension ChatAttachment {
    func base64ImageData() throws -> String {
        guard mimeType.hasPrefix("image/") else { throw LLMError.unsupportedImage(url) }
        return try Data(contentsOf: url).base64EncodedString()
    }

    func dataURL() throws -> String {
        "data:\(mimeType);base64,\(try base64ImageData())"
    }
}

private extension [String: JSONValue] {
    var foundationValue: [String: Any] {
        mapValues(\.foundationValue)
    }
}
