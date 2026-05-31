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

    func test_runDeletesDocumentsMissingFromSource() async throws {
        let (pipeline, store, _) = try makePipeline()
        _ = try await pipeline.run()

        try FileManager.default.removeItem(at: vault.appendingPathComponent("b.md"))
        _ = try await pipeline.run()

        let count = try await store.documentCount()
        XCTAssertEqual(count, 1)
    }

    func test_runReindexesWhenMetadataChanges() async throws {
        let embedder = HashingEmbeddingService(dimension: 64)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
        let connector = MutableDocumentConnector(document: ExtractedDocument(
            id: "doc",
            title: "Doc",
            text: "same text",
            contentHash: "same-hash",
            meta: ["source_url": "https://example.com/old"]
        ))
        let pipeline = IndexingPipeline(connectors: [connector], embedder: embedder, store: store)

        _ = try await pipeline.run()
        connector.document = ExtractedDocument(
            id: "doc",
            title: "Doc",
            text: "same text",
            contentHash: "same-hash",
            meta: ["source_url": "https://example.com/new"]
        )

        let stats = try await pipeline.run()
        let hits = try await store.search(
            try await embedder.embed(["same text"], kind: .query)[0],
            topK: 5
        )

        XCTAssertEqual(stats.indexed, 1)
        XCTAssertEqual(hits.first?.meta["source_url"], "https://example.com/new")
    }
}

private final class MutableDocumentConnector: SourceConnector, @unchecked Sendable {
    let sourceId = "mutable"
    let kind: SourceKind = .web
    var document: ExtractedDocument

    init(document: ExtractedDocument) {
        self.document = document
    }

    func enumerate() throws -> [SourceItem] {
        [SourceItem(id: document.id, uri: URL(fileURLWithPath: "/tmp/doc.html"), modifiedAt: nil)]
    }

    func extract(_ item: SourceItem) throws -> ExtractedDocument {
        document
    }
}
