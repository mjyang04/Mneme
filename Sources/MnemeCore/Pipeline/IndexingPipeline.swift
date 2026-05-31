import Foundation

public struct IndexRunStats: Sendable, Equatable {
    public var indexed: Int
    public var skipped: Int
    public var failed: Int
    public var deleted: Int

    public init(indexed: Int = 0, skipped: Int = 0, failed: Int = 0, deleted: Int = 0) {
        self.indexed = indexed
        self.skipped = skipped
        self.failed = failed
        self.deleted = deleted
    }
}

public actor IndexingPipeline {
    private let connectors: [any SourceConnector]
    private let embedder: any EmbeddingService
    private let store: IndexStore
    private let chunker: Chunker

    public init(
        connectors: [any SourceConnector],
        embedder: any EmbeddingService,
        store: IndexStore,
        chunker: Chunker = Chunker()
    ) {
        self.connectors = connectors
        self.embedder = embedder
        self.store = store
        self.chunker = chunker
    }

    public func run(progress: (@Sendable (String) -> Void)? = nil) async throws -> IndexRunStats {
        var stats = IndexRunStats()

        for connector in connectors {
            let items = try connector.enumerate()
            let currentDocumentIDs = Set(items.map(\.id))
            for item in items {
                do {
                    let document = try connector.extract(item)
                    let indexed = try await indexOne(
                        document: document,
                        sourceId: connector.sourceId,
                        kind: connector.kind,
                        uri: item.uri
                    )
                    if !indexed {
                        stats.skipped += 1
                        continue
                    }
                    stats.indexed += 1
                } catch {
                    stats.failed += 1
                    progress?("索引失败 \(item.uri.lastPathComponent): \(error.localizedDescription)")
                }
            }

            let indexedDocumentIDs = try await store.documentIDs(sourceId: connector.sourceId)
            for orphanedDocumentID in indexedDocumentIDs.subtracting(currentDocumentIDs) {
                try await store.deleteDocument(id: orphanedDocumentID)
                stats.deleted += 1
            }
        }

        return stats
    }

    @discardableResult
    public func indexOne(
        document: ExtractedDocument,
        sourceId: String,
        kind: SourceKind,
        uri: URL
    ) async throws -> Bool {
        if try await store.documentHash(id: document.id) == document.contentHash,
           try await store.documentMeta(id: document.id) == document.meta {
            return false
        }

        let chunks = chunker.chunk(document.text)
        guard !chunks.isEmpty else {
            return false
        }

        let vectors = try await embedder.embed(chunks.map(\.text), kind: .passage)
        try await store.upsert(
            documentId: document.id,
            sourceId: sourceId,
            kind: kind,
            uri: uri,
            title: document.title,
            contentHash: document.contentHash,
            meta: document.meta,
            chunks: chunks,
            vectors: vectors
        )
        return true
    }
}
