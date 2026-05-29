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

    func test_emptyQuery_returnsEmpty() async throws {
        let query = try await makeIndexed()
        let hits = try await query.search("   ")
        XCTAssertTrue(hits.isEmpty)
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
