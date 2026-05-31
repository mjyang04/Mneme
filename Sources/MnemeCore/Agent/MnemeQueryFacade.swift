import Foundation

public struct MnemeQueryFacade: Sendable {
    private let runtime: QueryServiceRuntime
    private let sourcesReader: SourcesReader

    public init(runtime: QueryServiceRuntime, sourcesReader: SourcesReader = SourcesReader()) {
        self.runtime = runtime
        self.sourcesReader = sourcesReader
    }

    public func search(
        query: String,
        topK: Int = 20,
        kinds: [SourceKind]? = nil,
        sourceIds: [String]? = nil
    ) async throws -> SearchResultDTO {
        let hits = try await runtime.query.search(
            query,
            topK: topK,
            filter: SearchFilter(kinds: kinds, sourceIds: sourceIds)
        )
        return SearchResultDTO(hits: hits.map(SearchHitDTO.init))
    }

    public func answer(
        question: String,
        topK: Int = 8,
        kinds: [SourceKind]? = nil,
        sourceIds: [String]? = nil
    ) async throws -> AnswerDTO {
        let answer = try await runtime.query.answer(
            question,
            topK: topK,
            filter: SearchFilter(kinds: kinds, sourceIds: sourceIds)
        )
        return AnswerDTO(
            answer: answer.text,
            citations: answer.citations.map(SearchHitDTO.init)
        )
    }

    public func sources() async throws -> SourcesResultDTO {
        let configured = sourcesReader.load()
        let configuredById = Dictionary(uniqueKeysWithValues: configured.map { ($0.id, $0) })
        let indexed = try await runtime.store.indexedSourceSummaries()
        let countsBySource = Dictionary(uniqueKeysWithValues: indexed.map { ($0.sourceId, $0) })

        var summaries = configured.map { source in
            SourceSummaryDTO(
                sourceId: source.id,
                kind: source.kind.rawValue,
                path: source.path,
                documentCount: countsBySource[source.id]?.documentCount ?? 0
            )
        }

        for summary in indexed where configuredById[summary.sourceId] == nil {
            summaries.append(SourceSummaryDTO(
                sourceId: summary.sourceId,
                kind: summary.kind.rawValue,
                path: "",
                documentCount: summary.documentCount
            ))
        }

        return SourcesResultDTO(sources: summaries.sorted {
                if $0.kind == $1.kind {
                    return $0.sourceId < $1.sourceId
                }
                return $0.kind < $1.kind
            })
    }

    public func remember(_ input: RememberInputDTO) async throws -> RememberResultDTO {
        let memoryStore = MemoryStore(
            directory: runtime.appSupportDirectory.appendingPathComponent("Memory", isDirectory: true)
        )
        let pipeline = IndexingPipeline(
            connectors: [],
            embedder: runtime.embedder,
            store: runtime.store
        )
        return try await MemoryService(memoryStore: memoryStore, pipeline: pipeline).remember(input)
    }

    public func doctor() async -> DoctorDTO {
        let documentCount = (try? await runtime.store.documentCount()) ?? 0
        return DoctorDTO(
            appSupportDir: runtime.appSupportDirectory.path,
            indexPath: runtime.databaseURL.path,
            indexReadable: FileManager.default.isReadableFile(atPath: runtime.databaseURL.path),
            documentCount: documentCount,
            embedderId: runtime.embedder.id,
            dimension: runtime.embedder.dimension,
            e5ResourcesPath: runtime.e5ResourcesURL?.path,
            capabilities: [
                "local-first",
                "search",
                "extractive-answer",
                "sources",
                "remember",
                "stdio-mcp"
            ]
        )
    }
}
