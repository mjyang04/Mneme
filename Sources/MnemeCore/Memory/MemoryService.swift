import Foundation

public struct MemoryService: Sendable {
    private let memoryStore: MemoryStore
    private let pipeline: IndexingPipeline
    private let connector: MemoryConnector

    public init(memoryStore: MemoryStore, pipeline: IndexingPipeline) {
        self.memoryStore = memoryStore
        self.pipeline = pipeline
        self.connector = MemoryConnector(
            root: memoryStore.directory,
            sourceId: MemoryStore.defaultSourceId
        )
    }

    public func remember(_ input: RememberInputDTO) async throws -> RememberResultDTO {
        let write = try memoryStore.write(input)
        let item = SourceItem(
            id: MemoryConnector.documentId(for: write.url),
            uri: write.url,
            modifiedAt: try? write.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )
        let document = try connector.extract(item)
        let indexed = try await pipeline.indexOne(
            document: document,
            sourceId: connector.sourceId,
            kind: connector.kind,
            uri: write.url
        )
        return RememberResultDTO(
            key: write.key,
            path: write.url.path,
            deduped: write.deduped,
            indexed: indexed
        )
    }
}
