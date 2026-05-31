import XCTest
@testable import MnemeCore

final class QueryServiceTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "deep learning neural networks gradient descent backpropagation"
            .write(to: vault.appendingPathComponent("ml.md"), atomically: true, encoding: .utf8)
        try "italian pasta tomato basil parmesan recipe kitchen"
            .write(to: vault.appendingPathComponent("food.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func makeIndexed() async throws -> QueryService {
        let embedder = HashingEmbeddingService(dimension: 512)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: 512)
        let pipeline = IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder,
            store: store
        )
        _ = try await pipeline.run()
        return QueryService(embedder: embedder, store: store)
    }

    func test_search_returnsRelevantDocFirst() async throws {
        let query = try await makeIndexed()
        let hits = try await query.search("neural network gradient learning", topK: 5)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits[0].uri.lastPathComponent, "ml.md")
    }

    func test_hybridSearchFindsExactTermsThatVectorModeCanMiss() async throws {
        let embedder = HashingEmbeddingService(dimension: 1)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
        try await store.upsert(
            documentId: "code",
            sourceId: "s1",
            kind: .code,
            uri: URL(fileURLWithPath: "/tmp/code.swift"),
            title: "code",
            contentHash: "h1",
            chunks: [Chunk(ordinal: 0, text: "The API symbol is MnemeQueryFacade.", locator: TextLocator())],
            vectors: [[1]]
        )
        try await store.upsert(
            documentId: "notes",
            sourceId: "s1",
            kind: .notes,
            uri: URL(fileURLWithPath: "/tmp/notes.md"),
            title: "notes",
            contentHash: "h2",
            chunks: [Chunk(ordinal: 0, text: "General local memory notes.", locator: TextLocator())],
            vectors: [[1]]
        )

        let query = QueryService(embedder: embedder, store: store)
        let hybrid = try await query.search("MnemeQueryFacade", topK: 1, mode: .hybrid)
        XCTAssertEqual(hybrid.first?.documentId, "code")
    }

    func test_emptyQuery_returnsEmpty() async throws {
        let query = try await makeIndexed()
        let hits = try await query.search("   ")
        XCTAssertTrue(hits.isEmpty)
    }

    func test_punctuationOnlyQuerySkipsLexicalSearchAndStillReturnsSafely() async throws {
        let query = try await makeIndexed()
        _ = try await query.search("!!! ...", topK: 5, mode: .hybrid)
    }

    func test_collapseByDocument_keepsBestPerDoc() {
        let url = URL(fileURLWithPath: "/x.md")
        func hit(_ document: String, _ score: Float) -> SearchHit {
            SearchHit(
                chunkId: "\(document)#\(score)",
                documentId: document,
                score: score,
                text: "t",
                title: document,
                uri: url,
                kind: .notes,
                locator: nil
            )
        }

        let collapsed = QueryService.collapseByDocument(
            [hit("A", 0.3), hit("A", 0.9), hit("B", 0.5)],
            topK: 10
        )
        XCTAssertEqual(collapsed.map(\.documentId), ["A", "B"])
        XCTAssertEqual(collapsed[0].score, 0.9)
    }
}
