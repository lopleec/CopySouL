import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var souls: [SoulPack] = []
    @Published var selectedSoulID: String? {
        didSet {
            if oldValue != selectedSoulID {
                messages = []
            }
        }
    }
    @Published var messages: [ChatMessage] = []
    @Published var draftText: String = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var statusText: String = "Ready"
    @Published var showingOnboarding: Bool = false
    @Published var configuration: LLMConfiguration
    @Published var apiKeyDraft: String = ""
    @Published var allowsScreenAccess: Bool = false
    @Published var isSidebarVisible: Bool = true
    @Published var soulSearchText: String = ""

    private let importer = SoulPackImporter()
    private let settingsStore = AppSettingsStore()
    private let keychain = KeychainStore()
    private let memoryStore: MemoryStore
    private let llmClient: LLMClient
    private let memorySummarizer: MemorySummarizer
    private lazy var toolRegistry = ToolRegistry(memoryStore: memoryStore)

    var selectedSoul: SoulPack? {
        souls.first { $0.id == selectedSoulID }
    }

    var filteredSouls: [SoulPack] {
        let query = soulSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return souls }
        return souls.filter { soul in
            soul.name.localizedCaseInsensitiveContains(query)
            || soul.soulDefinition.localizedCaseInsensitiveContains(query)
        }
    }

    var providerStatus: String {
        "\(configuration.provider.displayName) · \(configuration.chatModel)"
    }

    init() {
        let appSupport = Self.applicationSupportDirectory()
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("CopySouL.sqlite3")

        memoryStore = (try? MemoryStore(url: dbURL)) ?? (try! MemoryStore.inMemory())
        llmClient = LLMClient(keychain: keychain)
        memorySummarizer = MemorySummarizer(client: llmClient)
        configuration = settingsStore.loadConfiguration() ?? .defaultOpenAICompatible
        showingOnboarding = !settingsStore.hasCompletedOnboarding
        apiKeyDraft = (try? keychain.apiKey(account: configuration.apiKeyAccount)) ?? ""
        loadSouls()
    }

    func loadSouls() {
        do {
            souls = try memoryStore.fetchSouls()
            if !souls.contains(where: { $0.id == "default-soul-pack" }) {
                try saveDefaultSoulPack()
                souls = try memoryStore.fetchSouls()
            }
            if selectedSoulID == nil {
                selectedSoulID = souls.first?.id
            }
        } catch {
            statusText = "Failed to load SOULs: \(error.localizedDescription)"
        }
    }

    func importSoulPack(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        do {
            var pack = try importer.importPack(at: url)
            if souls.contains(where: { $0.name == pack.name && $0.rootURL == pack.rootURL }) {
                pack.name = "\(pack.name) \(souls.count + 1)"
            }
            try memoryStore.saveSoul(pack)
            loadSouls()
            selectedSoulID = pack.id
            statusText = pack.warnings.isEmpty ? "Imported \(pack.name)" : "Imported \(pack.name) with \(pack.warnings.count) warning(s)"
        } catch {
            statusText = "Import failed: \(error.localizedDescription)"
        }
    }

    func attachImages(from urls: [URL]) {
        let newAttachments = urls
            .filter { $0.isImageFile }
            .map { ChatAttachment(url: $0, mimeType: $0.inferredMIMEType) }
        pendingAttachments.append(contentsOf: newAttachments)
        if newAttachments.count != urls.count {
            statusText = "Only image attachments are supported in chat."
        }
    }

    func captureScreenshotAttachment() {
        Task {
            do {
                let url = try await ScreenshotService().captureScreenHidingApp()
                pendingAttachments.append(ChatAttachment(url: url, mimeType: "image/png"))
                statusText = "Screenshot attached"
            } catch {
                statusText = "Screenshot failed: \(error.localizedDescription)"
            }
        }
    }

    func removeAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func saveConfiguration() {
        do {
            configuration.normalizeModelLists()
            try settingsStore.saveConfiguration(configuration)
            if !apiKeyDraft.isEmpty || configuration.provider != .ollamaCompatible {
                try keychain.saveAPIKey(apiKeyDraft, account: configuration.apiKeyAccount)
            }
            showingOnboarding = false
            statusText = "Model settings saved"
        } catch {
            statusText = "Settings failed: \(error.localizedDescription)"
        }
    }

    func addModel(_ model: String, for slot: LLMModelSlot) {
        configuration.addModel(model, for: slot)
        persistConfiguration()
        statusText = "\(slot.title) model set to \(configuration.selectedModel(for: slot))"
    }

    func selectModel(_ model: String, for slot: LLMModelSlot) {
        configuration.selectModel(model, for: slot)
        persistConfiguration()
        statusText = "\(slot.title) model set to \(configuration.selectedModel(for: slot))"
    }

    func removeModel(_ model: String, for slot: LLMModelSlot) {
        configuration.removeModel(model, for: slot)
        persistConfiguration()
        statusText = "\(slot.title) model set to \(configuration.selectedModel(for: slot))"
    }

    func removeSelectedModel(for slot: LLMModelSlot) {
        removeModel(configuration.selectedModel(for: slot), for: slot)
    }

    func applyProviderDefaults() {
        configuration.applyProviderDefaults()
    }

    func toggleScreenAccess() {
        if allowsScreenAccess {
            allowsScreenAccess = false
            statusText = "Screen access disabled"
            return
        }

        if ScreenRecordingPermission.isGranted || ScreenRecordingPermission.request() {
            allowsScreenAccess = true
            statusText = "Screen access enabled"
        } else {
            allowsScreenAccess = false
            statusText = "Grant Screen Recording permission to let CopySouL see the screen."
            ScreenRecordingPermission.openSystemSettings()
        }
    }

    func sendMessage() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard let soul = selectedSoul else {
            statusText = "Import or select a SOUL first."
            return
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        messages.append(userMessage)
        draftText = ""
        pendingAttachments = []
        statusText = "Thinking with \(soul.name)..."

        Task {
            do {
                let assistant = try await completeTurn(userMessage: userMessage, soul: soul)
                messages.append(assistant)
                statusText = "Remembering useful details..."
                try await rememberTurn(userMessage: userMessage, assistant: assistant, soul: soul)
                statusText = "Ready"
            } catch {
                messages.append(ChatMessage(role: .assistant, content: "我现在连不上模型：\(error.localizedDescription)"))
                statusText = "Model error"
            }
        }
    }

    private func completeTurn(userMessage: ChatMessage, soul: SoulPack) async throws -> ChatMessage {
        let remembered = (try? memoryStore.search(soulID: soul.id, query: userMessage.content)) ?? []
        let system = systemPrompt(for: soul, memories: remembered)
        let history = messages.suffix(8).map { LLMMessage(role: $0.role, text: $0.content, attachments: $0.attachments) }
        let baseMessages = [LLMMessage(role: .system, text: system)] + history
        let tools = toolRegistry.tools(for: soul, allowsScreenshot: allowsScreenAccess)

        let first = try await llmClient.complete(
            configuration: configuration,
            messages: baseMessages,
            tools: tools,
            preferVision: userMessage.attachments.isEmpty == false
        )

        guard !first.toolCalls.isEmpty else {
            return ChatMessage(role: .assistant, content: first.text)
        }

        var selectedMeme: SoulAsset?
        var toolText = [String]()
        var toolAttachments = [ChatAttachment]()
        for call in first.toolCalls.prefix(3) {
            if call.name == "select_meme", selectedMeme != nil {
                continue
            }
            let result = await toolRegistry.execute(call, soul: soul)
            toolText.append("[\(call.name)] \(result.text)")
            if let attachment = result.attachment {
                toolAttachments.append(attachment)
            }
            if selectedMeme == nil {
                selectedMeme = result.selectedMeme
            }
        }

        let followUp = try await llmClient.complete(
            configuration: configuration,
            messages: baseMessages + [
                LLMMessage(role: .assistant, text: first.text),
                LLMMessage(role: .user, text: "Tool results:\n\(toolText.joined(separator: "\n"))", attachments: toolAttachments)
            ],
            tools: [],
            preferVision: !toolAttachments.isEmpty || !userMessage.attachments.isEmpty
        )
        return ChatMessage(role: .assistant, content: followUp.text, selectedMeme: selectedMeme)
    }

    private func rememberTurn(userMessage: ChatMessage, assistant: ChatMessage, soul: SoulPack) async throws {
        do {
            let batch = try await memorySummarizer.summarizeTurn(
                userText: userMessage.content,
                assistantText: assistant.content,
                configuration: configuration
            )
            try memoryStore.upsertCandidates(batch, soulID: soul.id)
        } catch {
            statusText = "Reply sent. Memory summary skipped: \(error.localizedDescription)"
        }
    }

    private func persistConfiguration() {
        configuration.normalizeModelLists()
        try? settingsStore.saveConfiguration(configuration)
    }

    private func systemPrompt(for soul: SoulPack, memories: [MemoryRecord]) -> String {
        let memoryBlock = memories.isEmpty
            ? "No durable memories were found for this SOUL."
            : memories.map { "- [\($0.kind.rawValue)] \($0.text)" }.joined(separator: "\n")
        let sentenceRule = soul.settings.allowMultiSentenceReplies
            ? "You may reply with one or several sentences when it feels natural."
            : "Keep replies to one sentence unless the user explicitly asks for detail."
        let memeRule = soul.settings.enableMemeReplies
            ? "If a meme would fit, call select_meme; still include a text reply."
            : "Do not use meme replies for this SOUL."
        let screenRule = allowsScreenAccess
            ? "If the user asks about the current screen, call take_screenshot before answering."
            : "You cannot see the user's screen right now. If the user asks about the screen, ask them to enable the eye button."

        return """
        You are CopySouL, a style-emulation chat app. Respond in the imported SOUL's speaking style, but do not claim to be the real person or imply you have their private thoughts.

        SOUL.md:
        \(soul.soulDefinition)

        Long-term memories for this SOUL only:
        \(memoryBlock)

        Reply policy:
        \(sentenceRule)
        \(memeRule)
        \(screenRule)
        Use memories only when relevant. Do not expose memory implementation details unless the user asks.
        Follow the user's language and intent. Be truthful about uncertainty and limitations.
        """
    }

    private func saveDefaultSoulPack() throws {
        let rootURL = Self.applicationSupportDirectory()
            .appendingPathComponent("DefaultSOULPack", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let soulDefinition =
        """
        # Default SOUL

        Speak naturally, clearly, and warmly. Keep answers concise unless the user asks for depth.

        ## Style
        - Helpful and direct
        - Calm, friendly, and not overly formal
        - Ask a short clarifying question only when needed

        ## Example
        User: 这个怎么弄？
        Assistant: 我先帮你把关键点拆开，然后直接动手改。
        """

        let settings = SoulSettings(
            enableMemeReplies: false,
            allowMultiSentenceReplies: true,
            displayName: "Default SOUL"
        )

        if !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("SOUL.md").path) {
            try soulDefinition.write(to: rootURL.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("setting.json").path) {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: rootURL.appendingPathComponent("setting.json"), options: .atomic)
        }

        try memoryStore.saveSoul(SoulPack(
            id: "default-soul-pack",
            name: "Default SOUL",
            rootURL: rootURL,
            soulDefinition: soulDefinition,
            settings: settings,
            assets: [],
            warnings: [],
            importedAt: Date(timeIntervalSince1970: 0)
        ))
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopySouL", isDirectory: true)
    }
}

private extension URL {
    var isImageFile: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(pathExtension.lowercased())
    }

    var inferredMIMEType: String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        default:
            return "image/png"
        }
    }
}
