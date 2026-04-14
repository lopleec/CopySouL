import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case claude
    case gemini
    case ollamaCompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI Compatible"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .ollamaCompatible:
            return "Ollama Compatible"
        }
    }
}

enum LLMModelSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat
    case vision
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Chat"
        case .vision:
            return "Vision"
        case .memory:
            return "Memory"
        }
    }
}

struct LLMConfiguration: Codable, Equatable, Sendable {
    var provider: ProviderKind
    var baseURL: URL
    var apiKeyAccount: String
    var chatModel: String
    var visionModel: String
    var memoryModel: String
    var chatModels: [String]
    var visionModels: [String]
    var memoryModels: [String]

    static let defaultOpenAICompatible = LLMConfiguration(
        provider: .openAICompatible,
        baseURL: URL(string: "https://api.openai.com")!,
        apiKeyAccount: "default",
        chatModel: "gpt-5.4",
        visionModel: "gpt-5.4",
        memoryModel: "gpt-5.4-mini"
    )

    init(
        provider: ProviderKind,
        baseURL: URL,
        apiKeyAccount: String,
        chatModel: String,
        visionModel: String,
        memoryModel: String,
        chatModels: [String] = [],
        visionModels: [String] = [],
        memoryModels: [String] = []
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKeyAccount = apiKeyAccount
        self.chatModel = chatModel
        self.visionModel = visionModel
        self.memoryModel = memoryModel
        self.chatModels = chatModels
        self.visionModels = visionModels
        self.memoryModels = memoryModels
        normalizeModelLists()
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case baseURL
        case apiKeyAccount
        case chatModel
        case visionModel
        case memoryModel
        case chatModels
        case visionModels
        case memoryModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ProviderKind.self, forKey: .provider)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        apiKeyAccount = try container.decode(String.self, forKey: .apiKeyAccount)
        chatModel = try container.decode(String.self, forKey: .chatModel)
        visionModel = try container.decode(String.self, forKey: .visionModel)
        memoryModel = try container.decode(String.self, forKey: .memoryModel)
        chatModels = try container.decodeIfPresent([String].self, forKey: .chatModels) ?? []
        visionModels = try container.decodeIfPresent([String].self, forKey: .visionModels) ?? []
        memoryModels = try container.decodeIfPresent([String].self, forKey: .memoryModels) ?? []
        normalizeModelLists()
    }

    mutating func normalizeModelLists() {
        chatModels = Self.normalizedModels(chatModels, selected: chatModel)
        visionModels = Self.normalizedModels(visionModels, selected: visionModel)
        memoryModels = Self.normalizedModels(memoryModels, selected: memoryModel)
    }

    func models(for slot: LLMModelSlot) -> [String] {
        switch slot {
        case .chat:
            return chatModels
        case .vision:
            return visionModels
        case .memory:
            return memoryModels
        }
    }

    func selectedModel(for slot: LLMModelSlot) -> String {
        switch slot {
        case .chat:
            return chatModel
        case .vision:
            return visionModel
        case .memory:
            return memoryModel
        }
    }

    mutating func selectModel(_ model: String, for slot: LLMModelSlot) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch slot {
        case .chat:
            chatModel = trimmed
        case .vision:
            visionModel = trimmed
        case .memory:
            memoryModel = trimmed
        }
        addModel(trimmed, for: slot, select: false)
    }

    mutating func addModel(_ model: String, for slot: LLMModelSlot, select: Bool = true) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch slot {
        case .chat:
            chatModels = Self.normalizedModels(chatModels + [trimmed], selected: select ? trimmed : chatModel)
            if select { chatModel = trimmed }
        case .vision:
            visionModels = Self.normalizedModels(visionModels + [trimmed], selected: select ? trimmed : visionModel)
            if select { visionModel = trimmed }
        case .memory:
            memoryModels = Self.normalizedModels(memoryModels + [trimmed], selected: select ? trimmed : memoryModel)
            if select { memoryModel = trimmed }
        }
    }

    mutating func removeModel(_ model: String, for slot: LLMModelSlot) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, models(for: slot).count > 1 else { return }

        switch slot {
        case .chat:
            var remaining = chatModels.filter { $0 != trimmed }
            if chatModel == trimmed {
                chatModel = remaining.first ?? Self.defaultModels(for: provider).chat
            }
            remaining.removeAll { $0 == chatModel }
            chatModels = Self.normalizedModels(remaining, selected: chatModel)
        case .vision:
            var remaining = visionModels.filter { $0 != trimmed }
            if visionModel == trimmed {
                visionModel = remaining.first ?? Self.defaultModels(for: provider).vision
            }
            remaining.removeAll { $0 == visionModel }
            visionModels = Self.normalizedModels(remaining, selected: visionModel)
        case .memory:
            var remaining = memoryModels.filter { $0 != trimmed }
            if memoryModel == trimmed {
                memoryModel = remaining.first ?? Self.defaultModels(for: provider).memory
            }
            remaining.removeAll { $0 == memoryModel }
            memoryModels = Self.normalizedModels(remaining, selected: memoryModel)
        }
    }

    mutating func applyProviderDefaults() {
        let defaults = Self.defaultModels(for: provider)
        if chatModel.isEmpty { chatModel = defaults.chat }
        if visionModel.isEmpty { visionModel = defaults.vision }
        if memoryModel.isEmpty { memoryModel = defaults.memory }
        addModel(defaults.chat, for: .chat, select: chatModel == defaults.chat)
        addModel(defaults.vision, for: .vision, select: visionModel == defaults.vision)
        addModel(defaults.memory, for: .memory, select: memoryModel == defaults.memory)
        normalizeModelLists()
    }

    static func defaultModels(for provider: ProviderKind) -> (chat: String, vision: String, memory: String) {
        switch provider {
        case .openAICompatible:
            return ("gpt-5.4", "gpt-5.4", "gpt-5.4-mini")
        case .claude:
            return ("claude-sonnet-4-5", "claude-sonnet-4-5", "claude-haiku-4-5")
        case .gemini:
            return ("gemini-2.5-pro", "gemini-2.5-pro", "gemini-2.5-flash")
        case .ollamaCompatible:
            return ("llama3.2", "llava", "llama3.2")
        }
    }

    private static func normalizedModels(_ models: [String], selected: String) -> [String] {
        var result: [String] = []
        for model in [selected] + models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return result
    }
}

struct LLMMessage: Equatable, Sendable {
    var role: ChatRole
    var text: String
    var attachments: [ChatAttachment]

    init(role: ChatRole, text: String, attachments: [ChatAttachment] = []) {
        self.role = role
        self.text = text
        self.attachments = attachments
    }
}

struct LLMTool: Equatable, Sendable {
    var name: String
    var description: String
    var parameters: [String: JSONValue]
}

struct LLMToolCall: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var argumentsJSON: String
}

struct LLMResult: Equatable, Sendable {
    var text: String
    var toolCalls: [LLMToolCall]
}

enum LLMError: Error, LocalizedError {
    case invalidBaseURL
    case unsupportedImage(URL)
    case responseFormat
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The configured model endpoint is invalid."
        case .unsupportedImage(let url):
            return "The image attachment could not be read: \(url.lastPathComponent)"
        case .responseFormat:
            return "The model response did not match the expected format."
        case .missingAPIKey:
            return "This provider needs an API key before CopySouL can chat."
        }
    }
}
