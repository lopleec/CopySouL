import Foundation

struct ToolExecutionResult: Equatable, Sendable {
    var text: String
    var attachment: ChatAttachment?
    var selectedMeme: SoulAsset?
}

@MainActor
struct ToolRegistry {
    private let memoryStore: MemoryStore
    private let screenshotService: ScreenshotService

    init(memoryStore: MemoryStore, screenshotService: ScreenshotService = ScreenshotService()) {
        self.memoryStore = memoryStore
        self.screenshotService = screenshotService
    }

    func tools(for soul: SoulPack, allowsScreenshot: Bool) -> [LLMTool] {
        var tools = [
            LLMTool(
                name: "memory_search",
                description: "Search long-term memories for this SOUL only. Use it when the user asks about prior facts, preferences, or context.",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search text for memories relevant to the current turn.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ]
            ),
        ]

        if allowsScreenshot {
            tools.append(LLMTool(
                name: "take_screenshot",
                description: "Capture the current screen when the user asks about what is visible on screen. CopySouL hides itself before capture.",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "reason": .object([
                            "type": .string("string"),
                            "description": .string("Why the screenshot is needed.")
                        ])
                    ])
                ]
            ))
        }

        if soul.settings.enableMemeReplies && soul.assets.contains(where: \.isToolEligible) {
            tools.append(LLMTool(
                name: "select_meme",
                description: "Select one matching meme from the current SOUL pack. Replies should include normal text plus the selected meme.",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Mood, situation, or meaning the meme should express.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ]
            ))
        }

        return tools
    }

    func execute(_ call: LLMToolCall, soul: SoulPack) async -> ToolExecutionResult {
        switch call.name {
        case "memory_search":
            let query = argument("query", from: call.argumentsJSON) ?? ""
            do {
                let records = try memoryStore.search(soulID: soul.id, query: query)
                let text = records.isEmpty
                    ? "No matching memories for this SOUL."
                    : records.map { "- [\($0.kind.rawValue)] \($0.text)" }.joined(separator: "\n")
                return ToolExecutionResult(text: text)
            } catch {
                return ToolExecutionResult(text: "memory_search failed: \(error.localizedDescription)")
            }
        case "take_screenshot":
            do {
                let url = try await screenshotService.captureScreenHidingApp()
                let attachment = ChatAttachment(url: url, mimeType: "image/png")
                return ToolExecutionResult(text: "Screenshot captured and attached.", attachment: attachment)
            } catch {
                return ToolExecutionResult(text: "take_screenshot failed: \(error.localizedDescription)")
            }
        case "select_meme":
            let query = argument("query", from: call.argumentsJSON) ?? call.argumentsJSON
            guard let meme = selectMeme(for: query, from: soul.assets) else {
                return ToolExecutionResult(text: "No eligible meme matched the request.")
            }
            return ToolExecutionResult(text: "Selected meme: \(meme.relativePath)", selectedMeme: meme)
        default:
            return ToolExecutionResult(text: "Tool \(call.name) is not allowed.")
        }
    }

    private func selectMeme(for query: String, from assets: [SoulAsset]) -> SoulAsset? {
        let candidates = assets.filter(\.isToolEligible)
        guard !candidates.isEmpty else { return nil }
        let tokens = Set(query.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))

        return candidates.max { lhs, rhs in
            score(lhs, tokens: tokens) < score(rhs, tokens: tokens)
        }
    }

    private func score(_ asset: SoulAsset, tokens: Set<String>) -> Int {
        let haystack = [asset.relativePath, asset.description ?? "", asset.usageHint ?? ""].joined(separator: " ").lowercased()
        guard !tokens.isEmpty else { return asset.isToolEligible ? 1 : 0 }
        return tokens.reduce(0) { partial, token in
            partial + (haystack.contains(token) ? 1 : 0)
        }
    }

    private func argument(_ key: String, from json: String) -> String? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object[key] as? String
    }
}
