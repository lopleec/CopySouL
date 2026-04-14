import XCTest
@testable import CopySouL

final class MemoryStoreTests: XCTestCase {
    func testMemorySearchIsIsolatedBySoul() throws {
        let store = try MemoryStore.inMemory()
        try saveSoul(id: "soul-a", in: store)
        try saveSoul(id: "soul-b", in: store)
        try store.upsertMemory(text: "User likes matcha.", kind: .preference, soulID: "soul-a")
        try store.upsertMemory(text: "User likes espresso.", kind: .preference, soulID: "soul-b")

        let results = try store.search(soulID: "soul-a", query: "matcha")

        XCTAssertEqual(results.map(\.text), ["User likes matcha."])
    }

    func testDuplicateMemoryBumpsWeightWithoutDuplicating() throws {
        let store = try MemoryStore.inMemory()
        try saveSoul(id: "soul-a", in: store)

        try store.upsertMemory(text: "User prefers concise replies.", kind: .preference, soulID: "soul-a")
        try store.upsertMemory(text: "User prefers concise replies.", kind: .preference, soulID: "soul-a")

        let memories = try store.allMemories(soulID: "soul-a")
        XCTAssertEqual(memories.count, 1)
        XCTAssertGreaterThan(memories[0].weight, 1.0)
    }

    func testStaleMemoryDecaysAndHitIncreasesWeight() throws {
        let store = try MemoryStore.inMemory()
        try saveSoul(id: "soul-a", in: store)
        let oldDate = Date(timeIntervalSinceNow: -100 * 24 * 60 * 60)
        let now = Date()
        try store.upsertMemory(text: "User likes jade tea.", kind: .preference, soulID: "soul-a", now: oldDate)

        _ = try store.search(soulID: "soul-a", query: "jade", now: now)
        let decayed = try store.allMemories(soulID: "soul-a")[0]
        XCTAssertLessThan(decayed.weight, 1.0)

        _ = try store.search(soulID: "soul-a", query: "jade", now: now.addingTimeInterval(60))
        let boosted = try store.allMemories(soulID: "soul-a")[0]
        XCTAssertGreaterThan(boosted.weight, decayed.weight)
    }

    func testCandidateBatchStoresKinds() throws {
        let store = try MemoryStore.inMemory()
        try saveSoul(id: "soul-a", in: store)
        try store.upsertCandidates(
            MemoryCandidateBatch(newFacts: ["User lives in Shanghai."], preferences: ["User prefers SwiftUI."], updates: ["User changed stack from Tauri to Swift."]),
            soulID: "soul-a"
        )

        let kinds = try store.allMemories(soulID: "soul-a").map(\.kind)
        XCTAssertEqual(Set(kinds), Set([.fact, .preference, .update]))
    }

    private func saveSoul(id: String, in store: MemoryStore) throws {
        try store.saveSoul(SoulPack(
            id: id,
            name: id,
            rootURL: FileManager.default.temporaryDirectory,
            soulDefinition: "style",
            settings: SoulSettings(),
            assets: [],
            warnings: [],
            importedAt: Date()
        ))
    }
}
