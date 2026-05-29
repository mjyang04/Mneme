import Foundation
import GRDB

public actor IndexStore {
    private let dbQueue: DatabaseQueue
    public let embedderId: String
    public let dimension: Int

    public init(path: String?, embedderId: String, dimension: Int) throws {
        if let path {
            self.dbQueue = try DatabaseQueue(path: path)
        } else {
            self.dbQueue = try DatabaseQueue()
        }
        self.embedderId = embedderId
        self.dimension = dimension

        try dbQueue.write { db in
            try Self.createSchema(db)
            try Self.ensureConfig(db, embedderId: embedderId, dimension: dimension)
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

    public func documentCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
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
        try dbQueue.write { db in
            try Self.deleteChunks(db, documentId: documentId)
            try db.execute(
                sql: """
                INSERT INTO documents(id, source_id, uri, title, content_hash, kind_raw, indexed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source_id = excluded.source_id,
                    uri = excluded.uri,
                    title = excluded.title,
                    content_hash = excluded.content_hash,
                    kind_raw = excluded.kind_raw,
                    indexed_at = excluded.indexed_at
                """,
                arguments: [
                    documentId,
                    sourceId,
                    uri.absoluteString,
                    title,
                    contentHash,
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
                    d.kind_raw AS kind_raw
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
                let kind = SourceKind(rawValue: kindRaw) ?? .notes

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

                scored.append(SearchHit(
                    chunkId: row["chunk_id"],
                    documentId: row["document_id"],
                    score: score,
                    text: row["text"],
                    title: row["title"],
                    uri: URL(string: uriString) ?? URL(fileURLWithPath: uriString),
                    kind: kind,
                    locator: locator
                ))
            }

            return Array(scored.sorted { $0.score > $1.score }.prefix(topK))
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
        CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(document_id);
        """)
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

    private static func deleteChunks(_ db: Database, documentId: String) throws {
        try db.execute(
            sql: """
            DELETE FROM chunk_vec
            WHERE chunk_id IN (SELECT id FROM chunks WHERE document_id = ?)
            """,
            arguments: [documentId]
        )
        try db.execute(sql: "DELETE FROM chunks WHERE document_id = ?", arguments: [documentId])
    }
}
