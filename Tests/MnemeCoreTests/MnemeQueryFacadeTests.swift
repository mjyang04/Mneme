import XCTest
@testable import MnemeCore

final class MnemeQueryFacadeTests: XCTestCase {
    private func makeRuntime() throws -> (QueryServiceRuntime, IndexStore) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mneme-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let embedder = HashingEmbeddingService(dimension: 32)
        let store = try IndexStore(
            path: databaseURL.path,
            embedderId: embedder.id,
            dimension: embedder.dimension
        )
        let query = QueryService(embedder: embedder, store: store)
        return (QueryServiceRuntime(
            appSupportDirectory: directory,
            databaseURL: databaseURL,
            embedder: embedder,
            store: store,
            query: query,
            e5ResourcesURL: nil
        ), store)
    }

    func test_facadeSearchAndAnswerUseDocumentedDTOShape() async throws {
        let (runtime, store) = try makeRuntime()
        try await store.upsert(
            documentId: "doc-a",
            sourceId: "source-notes",
            kind: .notes,
            uri: URL(fileURLWithPath: "/tmp/doc-a.md"),
            title: "Local Privacy",
            contentHash: "h1",
            meta: ["source_url": "https://example.com/local-privacy"],
            chunks: [Chunk(ordinal: 0, text: "Mneme keeps research data local on the Mac.", locator: TextLocator(startChar: 0, endChar: 44))],
            vectors: [try await runtime.embedder.embed(["Mneme keeps research data local on the Mac."], kind: .passage)[0]]
        )

        let facade = MnemeQueryFacade(runtime: runtime)
        let search = try await facade.search(query: "local research data", topK: 3)
        XCTAssertEqual(search.hits.first?.documentId, "doc-a")
        XCTAssertEqual(search.hits.first?.kind, "notes")
        XCTAssertEqual(search.hits.first?.title, "Local Privacy")
        XCTAssertEqual(search.hits.first?.sourceURL, "https://example.com/local-privacy")

        let answer = try await facade.answer(question: "Where does Mneme keep research data?", topK: 3)
        XCTAssertFalse(answer.answer.isEmpty)
        XCTAssertEqual(answer.citations.first?.documentId, "doc-a")

        let encoded = try JSONEncoder().encode(search)
        let decoded = try JSONDecoder().decode(SearchResultDTO.self, from: encoded)
        XCTAssertEqual(decoded, search)
    }

    func test_facadeSourcesCombinesConfiguredPathsWithIndexCounts() async throws {
        let (runtime, store) = try makeRuntime()
        try await store.upsert(
            documentId: "doc-a",
            sourceId: "source-notes",
            kind: .notes,
            uri: URL(fileURLWithPath: "/tmp/doc-a.md"),
            title: "A",
            contentHash: "h1",
            chunks: [Chunk(ordinal: 0, text: "alpha", locator: TextLocator())],
            vectors: [[1] + [Float](repeating: 0, count: runtime.embedder.dimension - 1)]
        )

        let key = "mneme.sources.test.\(UUID().uuidString)"
        let source = MnemeSourceConfig(id: "source-notes", kind: .notes, path: "/tmp/vault")
        UserDefaults.standard.set(try JSONEncoder().encode([source]), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let facade = MnemeQueryFacade(
            runtime: runtime,
            sourcesReader: SourcesReader(key: key, defaultsSuites: [])
        )
        let result = try await facade.sources()
        XCTAssertEqual(result.sources, [
            SourceSummaryDTO(sourceId: "source-notes", kind: "notes", path: "/tmp/vault", documentCount: 1)
        ])
    }
}
