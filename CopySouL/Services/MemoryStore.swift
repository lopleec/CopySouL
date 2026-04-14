import CryptoKit
import Foundation
import SQLite3

enum MemoryStoreError: LocalizedError {
    case openDatabase(String)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .openDatabase(let message), .sqlite(let message):
            return message
        }
    }
}

final class MemoryStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let minimumSearchWeight = 0.15

    init(path: String) throws {
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw MemoryStoreError.openDatabase("Could not open database at \(path).")
        }
        try migrate()
    }

    convenience init(url: URL) throws {
        try self.init(path: url.path)
    }

    deinit {
        sqlite3_close(db)
    }

    static func inMemory() throws -> MemoryStore {
        try MemoryStore(path: ":memory:")
    }

    func saveSoul(_ soul: SoulPack) throws {
        let settingsData = try encoder.encode(soul.settings)
        let settingsJSON = String(data: settingsData, encoding: .utf8) ?? "{}"
        try execute(
            """
            INSERT OR REPLACE INTO souls(id, name, root_path, soul_md, settings_json, imported_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                soul.id,
                soul.name,
                soul.rootURL.path,
                soul.soulDefinition,
                settingsJSON,
                soul.importedAt.timeIntervalSince1970
            ]
        )

        try execute("DELETE FROM assets WHERE soul_id = ?", [soul.id])
        for asset in soul.assets {
            try execute(
                """
                INSERT INTO assets(id, soul_id, relative_path, type, file_url, description, usage_hint, tool_eligible)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    asset.id,
                    asset.soulID,
                    asset.relativePath,
                    asset.type.rawValue,
                    asset.fileURL.path,
                    asset.description ?? "",
                    asset.usageHint ?? "",
                    asset.isToolEligible ? 1 : 0
                ]
            )
        }
    }

    func fetchSouls() throws -> [SoulPack] {
        var statement: OpaquePointer?
        let sql = "SELECT id, name, root_path, soul_md, settings_json, imported_at FROM souls ORDER BY imported_at DESC"
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        var souls = [SoulPack]()
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, 0)
            let settingsJSON = columnString(statement, 4)
            let settings = (try? decoder.decode(SoulSettings.self, from: Data(settingsJSON.utf8))) ?? SoulSettings()
            let assets = try fetchAssets(soulID: id)
            souls.append(SoulPack(
                id: id,
                name: columnString(statement, 1),
                rootURL: URL(fileURLWithPath: columnString(statement, 2)),
                soulDefinition: columnString(statement, 3),
                settings: settings,
                assets: assets,
                warnings: [],
                importedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        return souls
    }

    func fetchAssets(soulID: String) throws -> [SoulAsset] {
        var statement: OpaquePointer?
        try prepare(
            "SELECT id, soul_id, relative_path, type, file_url, description, usage_hint FROM assets WHERE soul_id = ? ORDER BY relative_path",
            statement: &statement
        )
        try bind([soulID], to: statement)
        defer { sqlite3_finalize(statement) }

        var assets = [SoulAsset]()
        while sqlite3_step(statement) == SQLITE_ROW {
            assets.append(SoulAsset(
                id: columnString(statement, 0),
                soulID: columnString(statement, 1),
                relativePath: columnString(statement, 2),
                fileURL: URL(fileURLWithPath: columnString(statement, 4)),
                type: SoulAssetType(rawValue: columnString(statement, 3)) ?? .other,
                description: columnString(statement, 5).nonEmpty,
                usageHint: columnString(statement, 6).nonEmpty
            ))
        }
        return assets
    }

    func upsertCandidates(_ batch: MemoryCandidateBatch, soulID: String, now: Date = Date()) throws {
        for text in batch.newFacts {
            try upsertMemory(text: text, kind: .fact, soulID: soulID, now: now)
        }
        for text in batch.preferences {
            try upsertMemory(text: text, kind: .preference, soulID: soulID, now: now)
        }
        for text in batch.updates {
            try upsertMemory(text: text, kind: .update, soulID: soulID, now: now)
        }
    }

    func upsertMemory(text rawText: String, kind: MemoryKind, soulID: String, now: Date = Date()) throws {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let hash = Self.sourceHash(soulID: soulID, kind: kind, text: text)

        if let existingID = try memoryID(forHash: hash, soulID: soulID) {
            try execute(
                "UPDATE memories SET weight = min(weight + 0.20, 3.0), last_used_at = ? WHERE id = ?",
                [now.timeIntervalSince1970, existingID]
            )
            return
        }

        let id = UUID().uuidString
        try execute(
            """
            INSERT INTO memories(id, soul_id, kind, text, weight, created_at, last_used_at, source_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [id, soulID, kind.rawValue, text, 1.0, now.timeIntervalSince1970, now.timeIntervalSince1970, hash]
        )
        try execute(
            "INSERT INTO memories_fts(memory_id, soul_id, text) VALUES (?, ?, ?)",
            [id, soulID, text]
        )
    }

    func search(soulID: String, query: String, limit: Int = 6, now: Date = Date()) throws -> [MemoryRecord] {
        try applyDecay(soulID: soulID, now: now)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let records: [MemoryRecord]
        if query.isEmpty {
            records = try topMemories(soulID: soulID, limit: limit)
        } else if let ftsRecords = try? searchFTS(soulID: soulID, query: query, limit: limit) {
            records = ftsRecords
        } else {
            records = try searchLike(soulID: soulID, query: query, limit: limit)
        }
        try markUsed(records, now: now)
        return records
    }

    func allMemories(soulID: String) throws -> [MemoryRecord] {
        try queryMemories(sql: "SELECT id, soul_id, kind, text, weight, created_at, last_used_at, source_hash FROM memories WHERE soul_id = ? ORDER BY created_at", bindings: [soulID])
    }

    private func migrate() throws {
        try execute("PRAGMA foreign_keys = ON")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS souls(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                root_path TEXT NOT NULL,
                soul_md TEXT NOT NULL,
                settings_json TEXT NOT NULL,
                imported_at REAL NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS assets(
                id TEXT PRIMARY KEY,
                soul_id TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                type TEXT NOT NULL,
                file_url TEXT NOT NULL,
                description TEXT,
                usage_hint TEXT,
                tool_eligible INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(soul_id) REFERENCES souls(id) ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS memories(
                id TEXT PRIMARY KEY,
                soul_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                text TEXT NOT NULL,
                weight REAL NOT NULL,
                created_at REAL NOT NULL,
                last_used_at REAL NOT NULL,
                source_hash TEXT NOT NULL,
                FOREIGN KEY(soul_id) REFERENCES souls(id) ON DELETE CASCADE
            )
            """
        )
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_memories_soul_hash ON memories(soul_id, source_hash)")
        try execute("CREATE INDEX IF NOT EXISTS idx_memories_soul_weight ON memories(soul_id, weight, last_used_at)")
        try execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
                memory_id UNINDEXED,
                soul_id UNINDEXED,
                text,
                tokenize = 'unicode61'
            )
            """
        )
    }

    private func applyDecay(soulID: String, now: Date, staleAfterDays: TimeInterval = 90) throws {
        let cutoff = now.addingTimeInterval(-staleAfterDays * 24 * 60 * 60).timeIntervalSince1970
        try execute(
            "UPDATE memories SET weight = max(weight * 0.50, 0.05) WHERE soul_id = ? AND last_used_at < ? AND weight > ?",
            [soulID, cutoff, minimumSearchWeight]
        )
    }

    private func searchFTS(soulID: String, query: String, limit: Int) throws -> [MemoryRecord] {
        try queryMemories(
            sql:
            """
            SELECT m.id, m.soul_id, m.kind, m.text, m.weight, m.created_at, m.last_used_at, m.source_hash
            FROM memories_fts
            JOIN memories m ON m.id = memories_fts.memory_id
            WHERE memories_fts MATCH ? AND m.soul_id = ? AND m.weight >= ?
            ORDER BY bm25(memories_fts), m.weight DESC
            LIMIT ?
            """,
            bindings: [Self.ftsQuery(from: query), soulID, minimumSearchWeight, limit]
        )
    }

    private func searchLike(soulID: String, query: String, limit: Int) throws -> [MemoryRecord] {
        try queryMemories(
            sql:
            """
            SELECT id, soul_id, kind, text, weight, created_at, last_used_at, source_hash
            FROM memories
            WHERE soul_id = ? AND text LIKE ? AND weight >= ?
            ORDER BY weight DESC, last_used_at DESC
            LIMIT ?
            """,
            bindings: [soulID, "%\(query)%", minimumSearchWeight, limit]
        )
    }

    private func topMemories(soulID: String, limit: Int) throws -> [MemoryRecord] {
        try queryMemories(
            sql:
            """
            SELECT id, soul_id, kind, text, weight, created_at, last_used_at, source_hash
            FROM memories
            WHERE soul_id = ? AND weight >= ?
            ORDER BY weight DESC, last_used_at DESC
            LIMIT ?
            """,
            bindings: [soulID, minimumSearchWeight, limit]
        )
    }

    private func markUsed(_ records: [MemoryRecord], now: Date) throws {
        for record in records {
            try execute(
                "UPDATE memories SET weight = min(weight + 0.10, 3.0), last_used_at = ? WHERE id = ?",
                [now.timeIntervalSince1970, record.id]
            )
        }
    }

    private func memoryID(forHash hash: String, soulID: String) throws -> String? {
        var statement: OpaquePointer?
        try prepare("SELECT id FROM memories WHERE soul_id = ? AND source_hash = ? LIMIT 1", statement: &statement)
        try bind([soulID, hash], to: statement)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return columnString(statement, 0)
    }

    private func queryMemories(sql: String, bindings: [Any]) throws -> [MemoryRecord] {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        try bind(bindings, to: statement)
        defer { sqlite3_finalize(statement) }

        var records = [MemoryRecord]()
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(MemoryRecord(
                id: columnString(statement, 0),
                soulID: columnString(statement, 1),
                kind: MemoryKind(rawValue: columnString(statement, 2)) ?? .fact,
                text: columnString(statement, 3),
                weight: sqlite3_column_double(statement, 4),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                sourceHash: columnString(statement, 7)
            ))
        }
        return records
    }

    private func execute(_ sql: String, _ bindings: [Any] = []) throws {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        try bind(bindings, to: statement)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MemoryStoreError.sqlite(lastError)
        }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MemoryStoreError.sqlite(lastError)
        }
    }

    private func bind(_ values: [Any], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case let value as String:
                status = sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            case let value as Double:
                status = sqlite3_bind_double(statement, position, value)
            case let value as Int:
                status = sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Int64:
                status = sqlite3_bind_int64(statement, position, value)
            case let value as Bool:
                status = sqlite3_bind_int(statement, position, value ? 1 : 0)
            default:
                status = sqlite3_bind_null(statement, position)
            }
            guard status == SQLITE_OK else {
                throw MemoryStoreError.sqlite(lastError)
            }
        }
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(db))
    }

    private static func sourceHash(soulID: String, kind: MemoryKind, text: String) -> String {
        let normalized = "\(soulID)|\(kind.rawValue)|\(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func ftsQuery(from text: String) -> String {
        let tokens = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"").trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        return tokens.isEmpty ? "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" : tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
