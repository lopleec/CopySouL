import Foundation

struct SoulSettings: Codable, Equatable, Sendable {
    var enableMemeReplies: Bool
    var allowMultiSentenceReplies: Bool
    var defaultModel: String?
    var displayName: String?
    var unknownFields: [String: JSONValue]

    init(
        enableMemeReplies: Bool = true,
        allowMultiSentenceReplies: Bool = true,
        defaultModel: String? = nil,
        displayName: String? = nil,
        unknownFields: [String: JSONValue] = [:]
    ) {
        self.enableMemeReplies = enableMemeReplies
        self.allowMultiSentenceReplies = allowMultiSentenceReplies
        self.defaultModel = defaultModel
        self.displayName = displayName
        self.unknownFields = unknownFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allValues = try container.allKeys.reduce(into: [String: JSONValue]()) { result, key in
            result[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }

        enableMemeReplies = Self.bool(from: allValues, keys: [
            "enableMemeReplies", "enable_meme_replies", "memeRepliesEnabled", "meme_replies_enabled", "表情包回复"
        ]) ?? true
        allowMultiSentenceReplies = Self.bool(from: allValues, keys: [
            "allowMultiSentenceReplies", "allow_multi_sentence_replies", "multiSentenceReplies", "multi_sentence_replies", "多句回复"
        ]) ?? true
        defaultModel = Self.string(from: allValues, keys: ["defaultModel", "default_model", "model"])
        displayName = Self.string(from: allValues, keys: ["displayName", "display_name", "name", "昵称"])

        let known = Set([
            "enableMemeReplies", "enable_meme_replies", "memeRepliesEnabled", "meme_replies_enabled", "表情包回复",
            "allowMultiSentenceReplies", "allow_multi_sentence_replies", "multiSentenceReplies", "multi_sentence_replies", "多句回复",
            "defaultModel", "default_model", "model",
            "displayName", "display_name", "name", "昵称"
        ])
        unknownFields = allValues.filter { !known.contains($0.key) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(enableMemeReplies, forKey: AnyCodingKey("enableMemeReplies"))
        try container.encode(allowMultiSentenceReplies, forKey: AnyCodingKey("allowMultiSentenceReplies"))
        try container.encodeIfPresent(defaultModel, forKey: AnyCodingKey("defaultModel"))
        try container.encodeIfPresent(displayName, forKey: AnyCodingKey("displayName"))
    }

    private static func bool(from values: [String: JSONValue], keys: [String]) -> Bool? {
        keys.compactMap { values[$0]?.boolValue }.first
    }

    private static func string(from values: [String: JSONValue], keys: [String]) -> String? {
        keys.compactMap { values[$0]?.stringValue }.first
    }
}

enum SoulAssetType: String, Codable, CaseIterable, Sendable {
    case meme
    case document
    case image
    case other
}

struct SoulAsset: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var soulID: String
    var relativePath: String
    var fileURL: URL
    var type: SoulAssetType
    var description: String?
    var usageHint: String?

    var isToolEligible: Bool {
        type == .meme && ((description?.isEmpty == false) || (usageHint?.isEmpty == false))
    }
}

struct SoulPack: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var rootURL: URL
    var soulDefinition: String
    var settings: SoulSettings
    var assets: [SoulAsset]
    var warnings: [String]
    var importedAt: Date
}

enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case fact
    case preference
    case update
}

struct MemoryRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var soulID: String
    var kind: MemoryKind
    var text: String
    var weight: Double
    var createdAt: Date
    var lastUsedAt: Date
    var sourceHash: String
}

struct MemoryCandidateBatch: Codable, Equatable, Sendable {
    var newFacts: [String]
    var preferences: [String]
    var updates: [String]
    var ignored: [String]

    init(newFacts: [String] = [], preferences: [String] = [], updates: [String] = [], ignored: [String] = []) {
        self.newFacts = newFacts
        self.preferences = preferences
        self.updates = updates
        self.ignored = ignored
    }
}

enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct ChatAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var url: URL
    var mimeType: String
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var role: ChatRole
    var content: String
    var attachments: [ChatAttachment] = []
    var selectedMeme: SoulAsset?
    var createdAt: Date = Date()
}
