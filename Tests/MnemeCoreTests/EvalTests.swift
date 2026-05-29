import XCTest
@testable import MnemeCore

final class EvalTests: XCTestCase {
    func test_hitAtK() {
        XCTAssertFalse(RetrievalEval.hitAtK(ranked: ["A", "B", "C"], relevant: ["C"], k: 2))
        XCTAssertTrue(RetrievalEval.hitAtK(ranked: ["A", "B", "C"], relevant: ["C"], k: 3))
    }

    func test_reciprocalRank() {
        XCTAssertEqual(RetrievalEval.reciprocalRank(ranked: ["A", "B"], relevant: ["B"]), 0.5)
        XCTAssertEqual(RetrievalEval.reciprocalRank(ranked: ["A", "B"], relevant: ["Z"]), 0.0)
    }

    func test_aggregate_meansAcrossQueries() {
        let aggregate = RetrievalEval.aggregate([
            (ranked: ["A", "B"], relevant: ["A"]),
            (ranked: ["A", "B"], relevant: ["B"])
        ], k: 2)
        XCTAssertEqual(aggregate.hitAtK, 1.0, accuracy: 1e-9)
        XCTAssertEqual(aggregate.mrr, 0.75, accuracy: 1e-9)
    }

    func test_endToEnd_evalOverFixtureVault() async throws {
        let vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let docs = [
            "ml.md": "deep learning neural networks gradient descent backpropagation training",
            "food.md": "italian pasta tomato basil parmesan recipe kitchen cooking",
            "stats.md": "probability distribution variance expectation random sampling statistics"
        ]
        for (name, body) in docs {
            try body.write(to: vault.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let embedder = HashingEmbeddingService(dimension: 512)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: 512)
        _ = try await IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder,
            store: store
        ).run()
        let query = QueryService(embedder: embedder, store: store)

        let cases: [(query: String, expected: String)] = [
            ("neural network gradient learning", "ml.md"),
            ("pasta tomato recipe cooking", "food.md"),
            ("probability variance sampling", "stats.md")
        ]

        var rankings: [(ranked: [String], relevant: Set<String>)] = []
        for testCase in cases {
            let hits = try await query.search(testCase.query, topK: 5)
            rankings.append((
                ranked: hits.map { $0.uri.lastPathComponent },
                relevant: [testCase.expected]
            ))
        }

        let aggregate = RetrievalEval.aggregate(rankings, k: 5)
        XCTAssertGreaterThanOrEqual(aggregate.hitAtK, 0.9)
        XCTAssertGreaterThanOrEqual(aggregate.mrr, 0.8)
    }
}
