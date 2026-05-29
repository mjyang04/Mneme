import XCTest
@testable import MnemeCore

final class IndexingPipelineTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "deep learning and neural networks"
            .write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "italian pasta recipes and tomato sauce"
            .write(to: vault.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func makePipeline() throws -> (IndexingPipeline, IndexStore, SpyEmbeddingService) {
        let embedder = SpyEmbeddingService(base: HashingEmbeddingService(dimension: 64))
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: 64)
        let pipeline = IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder,
            store: store
        )
        return (pipeline, store, embedder)
    }

    func test_run_indexesAllDocuments() async throws {
        let (pipeline, store, _) = try makePipeline()
        let stats = try await pipeline.run()
        let count = try await store.documentCount()
        XCTAssertEqual(stats.indexed, 2)
        XCTAssertEqual(count, 2)
    }

    func test_secondRun_skipsUnchanged_noReembed() async throws {
        let (pipeline, _, spy) = try makePipeline()
        _ = try await pipeline.run()
        let embeddedAfterFirst = await spy.totalTextsEmbedded

        let stats = try await pipeline.run()
        let embeddedAfterSecond = await spy.totalTextsEmbedded
        XCTAssertEqual(stats.indexed, 0)
        XCTAssertEqual(stats.skipped, 2)
        XCTAssertEqual(embeddedAfterSecond, embeddedAfterFirst)
    }
}
