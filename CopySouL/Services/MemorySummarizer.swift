import Foundation

struct MemorySummarizer {
    private let client: LLMClient

    init(client: LLMClient = LLMClient()) {
        self.client = client
    }

    func summarizeTurn(userText: String, assistantText: String, configuration: LLMConfiguration) async throws -> MemoryCandidateBatch {
        var memoryConfiguration = configuration
        memoryConfiguration.chatModel = configuration.memoryModel
        memoryConfiguration.visionModel = configuration.memoryModel

        let prompt =
        """
        Extract durable memory candidates from this turn. Return JSON only with these keys:
        newFacts: string[]
        preferences: string[]
        updates: string[]
        ignored: string[]

        Store only stable facts or preferences that may matter in future conversations. Ignore transient wording, greetings, and one-off tasks.
        """
        let user =
        """
        User:
        \(userText)

        Assistant:
        \(assistantText)
        """
        let result = try await client.complete(
            configuration: memoryConfiguration,
            messages: [
                LLMMessage(role: .system, text: prompt),
                LLMMessage(role: .user, text: user)
            ]
        )
        return try Self.decodeBatch(from: result.text)
    }

    static func decodeBatch(from text: String) throws -> MemoryCandidateBatch {
        let jsonText = text.jsonObjectSlice ?? text
        let data = Data(jsonText.utf8)
        return try JSONDecoder().decode(MemoryCandidateBatch.self, from: data)
    }
}

private extension String {
    var jsonObjectSlice: String? {
        guard let start = firstIndex(of: "{"), let end = lastIndex(of: "}"), start <= end else { return nil }
        return String(self[start...end])
    }
}
