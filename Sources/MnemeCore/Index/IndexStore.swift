import Foundation
import GRDB

public actor IndexStore {
    private let dbQueue: DatabaseQueue
    private let hasMetaJSON: Bool
    public let embedderId: String
    public let dimension: Int

    public init(path: String?, embedderId: String, dimension: Int) throws {
        let queue: DatabaseQueue
        if let path {
            queue = try DatabaseQueue(path: path)
        } else {
            queue = try DatabaseQueue()
        }
        self.dbQueue = queue
        self.hasMetaJSON = true
        self.embedderId = embedderId
        self.dimension = dimension

        try dbQueue.writeWithoutTransaction { db in
            try Self.enableWAL(db)
        }
        try dbQueue.write { db in
            try Self.createSchema(db)
            try Self.ensureConfig(db, embedderId: embedderId, dimension: dimension)
            try Self.backfillFTSIfNeeded(db)
        }
    }

    public init(readonlyPath path: String, embedderId: String, dimension: Int) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        let hasMetaJSON = try queue.read { db in
            try Self.columnExists(db, table: "documents", column: "meta_json")
        }
        self.dbQueue = queue
        self.hasMetaJSON = hasMetaJSON
        self.embedderId = embedderId
        self.dimension = dimension

        try dbQueue.read { db in
            try Self.validateConfig(db, embedderId: embedderId, dimension: dimension)
        }
    }

    public static func readConfig(path: String) throws -> IndexStoreConfig? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        var configuration = Configuration()
        configuration.readonly = true
        let dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM config")
            let existing = rows.reduce(into: [String: String]()) { result, row in
                let key: String = row["key"]
                let value: String = row["value"]
                result[key] = value
            }
            guard let embedderId = existing["embedder_id"],
                  let dimensionRaw = existing["dimension"],
                  let dimension = Int(dimensionRaw) else {
                return nil
            }
            return IndexStoreConfig(embedderId: embedderId, dimension: dimension)
        }
    }

    public func documentHash(id: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT content_hash FROM documents WHERE id = ?",
                arguments: [id]
            )
        }
    }

    public func documentMeta(id: String) throws -> [String: String]? {
        guard hasMetaJSON else {
            return nil
        }
        return try dbQueue.read { db -> [String: String]? in
            guard let metaJSON = try String.fetchOne(
                db,
                sql: "SELECT meta_json FROM documents WHERE id = ?",
                arguments: [id]
            ) else {
                return nil
            }
            return Self.decodeMeta(metaJSON)
        }
    }

    public func documentCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
        }
    }

    public func documentCount(sourceId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM documents WHERE source_id = ?",
                arguments: [sourceId]
            ) ?? 0
        }
    }

    public func indexedSourceSummaries() throws -> [IndexedSourceSummary] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT source_id, kind_raw, COUNT(*) AS document_count
                FROM documents
                GROUP BY source_id, kind_raw
                ORDER BY source_id, kind_raw
                """
            )
            return rows.map { row in
                let kindRaw: String = row["kind_raw"]
                return IndexedSourceSummary(
                    sourceId: row["source_id"],
                    kind: SourceKind.parse(kindRaw) ?? .notes,
                    documentCount: row["document_count"]
                )
            }
        }
    }

    public func documentIDs(sourceId: String) throws -> Set<String> {
        try dbQueue.read { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM documents WHERE source_id = ?",
                arguments: [sourceId]
            )
            return Set(ids)
        }
    }

    public func deleteDocument(id: String) throws {
        try dbQueue.write { db in
            try Self.deleteChunks(db, documentId: id)
            try db.execute(sql: "DELETE FROM documents WHERE id = ?", arguments: [id])
        }
    }

    public func upsert(
        documentId: String,
        sourceId: String,
        kind: SourceKind,
        uri: URL,
        title: String?,
        contentHash: String,
        meta: [String: String] = [:],
        chunks: [Chunk],
        vectors: [[Float]]
    ) throws {
        guard chunks.count == vectors.count else {
            throw EmbeddingError.dimensionMismatch
        }
        guard vectors.allSatisfy({ $0.count == dimension }) else {
            throw EmbeddingError.dimensionMismatch
        }

        let encoder = JSONEncoder()
        let metaData = try encoder.encode(meta)
        let metaJSON = String(data: metaData, encoding: .utf8) ?? "{}"
        try dbQueue.write { db in
            try Self.deleteChunks(db, documentId: documentId)
            try db.execute(
                sql: """
                INSERT INTO documents(id, source_id, uri, title, content_hash, meta_json, kind_raw, indexed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source_id = excluded.source_id,
                    uri = excluded.uri,
                    title = excluded.title,
                    content_hash = excluded.content_hash,
                    meta_json = excluded.meta_json,
                    kind_raw = excluded.kind_raw,
                    indexed_at = excluded.indexed_at
                """,
                arguments: [
                    documentId,
                    sourceId,
                    uri.absoluteString,
                    title,
                    contentHash,
                    metaJSON,
                    kind.rawValue,
                    Date().timeIntervalSince1970
                ]
            )

            for (chunk, vector) in zip(chunks, vectors) {
                let chunkId = "\(documentId)#\(chunk.ordinal)"
                let locatorData = try encoder.encode(chunk.locator)
                let locatorJSON = String(data: locatorData, encoding: .utf8) ?? "{}"

                try db.execute(
                    sql: """
                    INSERT INTO chunks(id, document_id, ordinal, text, locator_json)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [chunkId, documentId, chunk.ordinal, chunk.text, locatorJSON]
                )
                try db.execute(
                    sql: "INSERT INTO chunk_vec(chunk_id, embedding) VALUES (?, ?)",
                    arguments: [chunkId, vector.data]
                )
                try db.execute(
                    sql: "INSERT INTO chunk_fts(chunk_id, text) VALUES (?, ?)",
                    arguments: [chunkId, FtsQueryBuilder.indexText(chunk.text)]
                )
            }
        }
    }

    public func search(
        _ queryVector: [Float],
        topK: Int,
        filter: SearchFilter? = nil
    ) throws -> [SearchHit] {
        guard queryVector.count == dimension else {
            throw EmbeddingError.dimensionMismatch
        }
        guard topK > 0 else { return [] }

        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let metaSelect = hasMetaJSON ? "d.meta_json AS meta_json" : "'{}' AS meta_json"
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    v.chunk_id AS chunk_id,
                    v.embedding AS embedding,
                    c.document_id AS document_id,
                    c.text AS text,
                    c.locator_json AS locator_json,
                    d.source_id AS source_id,
                    d.title AS title,
                    d.uri AS uri,
                    d.kind_raw AS kind_raw,
                    \(metaSelect)
                FROM chunk_vec v
                JOIN chunks c ON c.id = v.chunk_id
                JOIN documents d ON d.id = c.document_id
                """
            )

            var scored: [SearchHit] = []
            scored.reserveCapacity(rows.count)

            for row in rows {
                let sourceId: String = row["source_id"]
                let kindRaw: String = row["kind_raw"]
                let kind = SourceKind.parse(kindRaw) ?? .notes

                if let kinds = filter?.kinds, !kinds.contains(kind) {
                    continue
                }
                if let sourceIds = filter?.sourceIds, !sourceIds.contains(sourceId) {
                    continue
                }

                let embeddingData: Data = row["embedding"]
                let score = Vector.dot(queryVector, [Float](data: embeddingData))
                let locatorJSON: String = row["locator_json"]
                let locator = try? decoder.decode(TextLocator.self, from: Data(locatorJSON.utf8))
                let uriString: String = row["uri"]
                let metaJSON: String = row["meta_json"]

                scored.append(SearchHit(
                    chunkId: row["chunk_id"],
                    documentId: row["document_id"],
                    score: score,
                    text: row["text"],
                    title: row["title"],
                    uri: URL(string: uriString) ?? URL(fileURLWithPath: uriString),
                    kind: kind,
                    locator: locator,
                    meta: Self.decodeMeta(metaJSON)
                ))
            }

            return Array(scored.sorted { $0.score > $1.score }.prefix(topK))
        }
    }

    public func searchLexical(
        _ ftsQuery: String,
        topK: Int,
        filter: SearchFilter? = nil
    ) throws -> [SearchHit] {
        let trimmed = ftsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, topK > 0 else { return [] }

        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let metaSelect = hasMetaJSON ? "d.meta_json AS meta_json" : "'{}' AS meta_json"
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    chunk_fts.chunk_id AS chunk_id,
                    bm25(chunk_fts) AS rank,
                    c.document_id AS document_id,
                    c.text AS text,
                    c.locator_json AS locator_json,
                    d.source_id AS source_id,
                    d.title AS title,
                    d.uri AS uri,
                    d.kind_raw AS kind_raw,
                    \(metaSelect)
                FROM chunk_fts
                JOIN chunks c ON c.id = chunk_fts.chunk_id
                JOIN documents d ON d.id = c.document_id
                WHERE chunk_fts MATCH ?
                ORDER BY rank
                """,
                arguments: [trimmed]
            )

            var scored: [SearchHit] = []
            scored.reserveCapacity(rows.count)

            for row in rows {
                let sourceId: String = row["source_id"]
                let kindRaw: String = row["kind_raw"]
                let kind = SourceKind.parse(kindRaw) ?? .notes

                if let kinds = filter?.kinds, !kinds.contains(kind) {
                    continue
                }
                if let sourceIds = filter?.sourceIds, !sourceIds.contains(sourceId) {
                    continue
                }

                let rank: Double = row["rank"]
                let locatorJSON: String = row["locator_json"]
                let locator = try? decoder.decode(TextLocator.self, from: Data(locatorJSON.utf8))
                let uriString: String = row["uri"]
                let metaJSON: String = row["meta_json"]
                scored.append(SearchHit(
                    chunkId: row["chunk_id"],
                    documentId: row["document_id"],
                    score: Float(-rank),
                    text: row["text"],
                    title: row["title"],
                    uri: URL(string: uriString) ?? URL(fileURLWithPath: uriString),
                    kind: kind,
                    locator: locator,
                    meta: Self.decodeMeta(metaJSON)
                ))
            }

            return Array(scored.prefix(topK))
        }
    }

    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS config (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            uri TEXT NOT NULL,
            title TEXT,
            content_hash TEXT NOT NULL,
            meta_json TEXT NOT NULL DEFAULT '{}',
            kind_raw TEXT NOT NULL,
            indexed_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            text TEXT NOT NULL,
            locator_json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chunk_vec (
            chunk_id TEXT PRIMARY KEY,
            embedding BLOB NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(
            chunk_id UNINDEXED,
            text,
            tokenize = 'unicode61'
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(document_id);
        """)
        try ensureColumn(
            db,
            table: "documents",
            column: "meta_json",
            addColumnSQL: "ALTER TABLE documents ADD COLUMN meta_json TEXT NOT NULL DEFAULT '{}'"
        )
    }

    private static func enableWAL(_ db: Database) throws {
        _ = try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL")
    }

    private static func ensureConfig(
        _ db: Database,
        embedderId: String,
        dimension: Int
    ) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM config")
        let existing = rows.reduce(into: [String: String]()) { result, row in
            let key: String = row["key"]
            let value: String = row["value"]
            result[key] = value
        }

        if let existingEmbedderId = existing["embedder_id"] {
            guard existingEmbedderId == embedderId,
                  existing["dimension"] == String(dimension) else {
                throw EmbeddingError.dimensionMismatch
            }
        } else {
            try db.execute(
                sql: "INSERT INTO config(key, value) VALUES (?, ?), (?, ?)",
                arguments: ["embedder_id", embedderId, "dimension", String(dimension)]
            )
        }
    }

    private static func validateConfig(
        _ db: Database,
        embedderId: String,
        dimension: Int
    ) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM config")
        let existing = rows.reduce(into: [String: String]()) { result, row in
            let key: String = row["key"]
            let value: String = row["value"]
            result[key] = value
        }

        guard existing["embedder_id"] == embedderId,
              existing["dimension"] == String(dimension) else {
            throw EmbeddingError.dimensionMismatch
        }
    }

    private static func deleteChunks(_ db: Database, documentId: String) throws {
        try db.execute(
            sql: """
            DELETE FROM chunk_fts
            WHERE chunk_id IN (SELECT id FROM chunks WHERE document_id = ?)
            """,
            arguments: [documentId]
        )
        try db.execute(
            sql: """
            DELETE FROM chunk_vec
            WHERE chunk_id IN (SELECT id FROM chunks WHERE document_id = ?)
            """,
            arguments: [documentId]
        )
        try db.execute(sql: "DELETE FROM chunks WHERE document_id = ?", arguments: [documentId])
    }

    private static func backfillFTSIfNeeded(_ db: Database) throws {
        let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunk_fts") ?? 0
        guard ftsCount == 0 else {
            return
        }
        let chunkCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunks") ?? 0
        guard chunkCount > 0 else {
            return
        }

        let rows = try Row.fetchAll(db, sql: "SELECT id, text FROM chunks ORDER BY id")
        for row in rows {
            let chunkId: String = row["id"]
            let text: String = row["text"]
            try db.execute(
                sql: "INSERT INTO chunk_fts(chunk_id, text) VALUES (?, ?)",
                arguments: [chunkId, FtsQueryBuilder.indexText(text)]
            )
        }
    }

    private static func ensureColumn(
        _ db: Database,
        table: String,
        column: String,
        addColumnSQL: String
    ) throws {
        if try !columnExists(db, table: table, column: column) {
            try db.execute(sql: addColumnSQL)
        }
    }

    private static func columnExists(_ db: Database, table: String, column: String) throws -> Bool {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        return rows.contains { row in
            let name: String = row["name"]
            return name == column
        }
    }

    private static func decodeMeta(_ metaJSON: String) -> [String: String] {
        guard let data = metaJSON.data(using: .utf8),
              let meta = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return meta
    }
}

public struct IndexedSourceSummary: Sendable, Equatable {
    public let sourceId: String
    public let kind: SourceKind
    public let documentCount: Int

    public init(sourceId: String, kind: SourceKind, documentCount: Int) {
        self.sourceId = sourceId
        self.kind = kind
        self.documentCount = documentCount
    }
}

public struct IndexStoreConfig: Sendable, Equatable {
    public let embedderId: String
    public let dimension: Int

    public init(embedderId: String, dimension: Int) {
        self.embedderId = embedderId
        self.dimension = dimension
    }
}
