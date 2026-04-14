import XCTest
@testable import CopySouL

final class LLMProviderTests: XCTestCase {
    private var imageURL: URL!

    override func setUpWithError() throws {
        imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("copysoul-provider-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: imageURL)
    }

    func testOpenAICompatibleBuildsVisionAndToolRequest() throws {
        let provider = OpenAICompatibleProvider()
        let request = try provider.makeRequest(
            configuration: LLMConfiguration.defaultOpenAICompatible,
            apiKey: "test-key",
            messages: [LLMMessage(role: .user, text: "look", attachments: [ChatAttachment(url: imageURL, mimeType: "image/png")])],
            tools: [sampleTool],
            preferVision: true
        )
        let body = try requestBody(request)

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertNotNil(body["tools"])
        XCTAssertEqual(body["model"] as? String, "gpt-5.4")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
    }

    func testClaudeBuildsMessagesRequest() throws {
        let configuration = LLMConfiguration(
            provider: .claude,
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKeyAccount: "default",
            chatModel: "claude-sonnet",
            visionModel: "claude-sonnet",
            memoryModel: "claude-haiku"
        )

        let request = try ClaudeProvider().makeRequest(
            configuration: configuration,
            apiKey: "test-key",
            messages: [LLMMessage(role: .system, text: "style"), LLMMessage(role: .user, text: "hi")],
            tools: [sampleTool],
            preferVision: false
        )
        let body = try requestBody(request)

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(body["system"] as? String, "style")
        XCTAssertNotNil(body["tools"])
    }

    func testGeminiBuildsGenerateContentRequest() throws {
        let configuration = LLMConfiguration(
            provider: .gemini,
            baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            apiKeyAccount: "default",
            chatModel: "gemini-pro",
            visionModel: "gemini-pro-vision",
            memoryModel: "gemini-flash"
        )

        let request = try GeminiProvider().makeRequest(
            configuration: configuration,
            apiKey: "gemini-key",
            messages: [LLMMessage(role: .user, text: "hi")],
            tools: [sampleTool],
            preferVision: true
        )
        let body = try requestBody(request)

        XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
        XCTAssertTrue(request.url?.absoluteString.contains("gemini-pro-vision:generateContent") == true)
        XCTAssertTrue(request.url?.absoluteString.contains("key=gemini-key") == true)
        XCTAssertNotNil(body["tools"])
    }

    func testOllamaBuildsLocalRequestWithoutRequiredAPIKey() throws {
        let configuration = LLMConfiguration(
            provider: .ollamaCompatible,
            baseURL: URL(string: "http://localhost:11434")!,
            apiKeyAccount: "default",
            chatModel: "llama3.2",
            visionModel: "llava",
            memoryModel: "llama3.2"
        )

        let request = try OllamaCompatibleProvider().makeRequest(
            configuration: configuration,
            apiKey: nil,
            messages: [LLMMessage(role: .user, text: "hi")],
            tools: [sampleTool],
            preferVision: false
        )
        let body = try requestBody(request)

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(body["model"] as? String, "llama3.2")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    private var sampleTool: LLMTool {
        LLMTool(
            name: "memory_search",
            description: "Search memory",
            parameters: [
                "type": .string("object"),
                "properties": .object(["query": .object(["type": .string("string")])])
            ]
        )
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}
