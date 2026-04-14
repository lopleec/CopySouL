import XCTest
@testable import CopySouL

final class SoulPackImporterTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("CopySouLTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testImportsFlexibleAssetRootAndMemeMarkdownDescriptions() throws {
        try write("SOUL style", to: tempRoot.appendingPathComponent("SOUL.md"))
        try write(#"{"display_name":"Alice","enable_meme_replies":true,"custom_field":"kept"}"#, to: tempRoot.appendingPathComponent("setting.json"))

        let memeDirectory = tempRoot.appendingPathComponent("asset/表情包", isDirectory: true)
        try FileManager.default.createDirectory(at: memeDirectory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: memeDirectory.appendingPathComponent("A.png"))
        try Data([0x02]).write(to: memeDirectory.appendingPathComponent("B.jpg"))
        try Data([0x03]).write(to: memeDirectory.appendingPathComponent("C.gif"))
        try write(
            """
            A.png 画面内容：开心拍桌。什么时候用：用户成功了。
            C.gif 画面内容：无语转头。什么时候用：吐槽。
            """,
            to: memeDirectory.appendingPathComponent("memes.md")
        )

        let pack = try SoulPackImporter().importPack(at: tempRoot)

        XCTAssertEqual(pack.name, "Alice")
        XCTAssertEqual(pack.settings.unknownFields["custom_field"], .string("kept"))
        XCTAssertEqual(pack.assets.filter { $0.type == .meme }.count, 3)
        XCTAssertEqual(pack.assets.filter(\.isToolEligible).count, 2)
        XCTAssertTrue(pack.warnings.contains { $0.contains("B.jpg") })
    }

    func testMissingOptionalAssetsStillImports() throws {
        try write("SOUL style", to: tempRoot.appendingPathComponent("SOUL.md"))
        try write("{}", to: tempRoot.appendingPathComponent("setting.json"))

        let pack = try SoulPackImporter().importPack(at: tempRoot)

        XCTAssertEqual(pack.assets.count, 0)
        XCTAssertTrue(pack.settings.enableMemeReplies)
        XCTAssertTrue(pack.settings.allowMultiSentenceReplies)
    }

    func testRequiresSoulAndSettingsFiles() throws {
        try write("{}", to: tempRoot.appendingPathComponent("setting.json"))
        XCTAssertThrowsError(try SoulPackImporter().importPack(at: tempRoot))

        try write("SOUL style", to: tempRoot.appendingPathComponent("SOUL.md"))
        try FileManager.default.removeItem(at: tempRoot.appendingPathComponent("setting.json"))
        XCTAssertThrowsError(try SoulPackImporter().importPack(at: tempRoot))
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
