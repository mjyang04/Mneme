import Foundation

public struct IndexRunStats: Sendable, Equatable {
    public var indexed: Int
    public var skipped: Int
    public var failed: Int

    public init(indexed: Int = 0, skipped: Int = 0, failed: Int = 0) {
        self.indexed = indexed
        self.skipped = skipped
        self.failed = failed
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
            for item in items {
                do {
                    let document = try connector.extract(item)
                    if try await store.documentHash(id: document.id) == document.contentHash {
                        stats.skipped += 1
                        continue
                    }

                    let chunks = chunker.chunk(document.text)
                    guard !chunks.isEmpty else {
                        stats.skipped += 1
                        continue
                    }

                    let vectors = try await embedder.embed(chunks.map(\.text), kind: .passage)
                    try await store.upsert(
                        documentId: document.id,
                        sourceId: connector.sourceId,
                        kind: connector.kind,
                        uri: item.uri,
                        title: document.title,
                        contentHash: document.contentHash,
                        chunks: chunks,
                        vectors: vectors
                    )
                    stats.indexed += 1
                } catch {
                    stats.failed += 1
                    progress?("索引失败 \(item.uri.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        return stats
    }
}
