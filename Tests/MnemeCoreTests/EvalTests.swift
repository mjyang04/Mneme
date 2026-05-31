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

        let cases = try loadEvalCases()

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

    func test_hybridEvalNotWorseThanVectorOverFixtureVault() async throws {
        let vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hybrid-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let docs = [
            "api.md": "The Swift facade type is MnemeQueryFacade and it maps search DTOs.",
            "memory.md": "Managed memory notes are markdown files in Application Support.",
            "cn.md": "本地研究方法使用语义索引和关键词检索。"
        ]
        for (name, body) in docs {
            try body.write(to: vault.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let embedder = HashingEmbeddingService(dimension: 128)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
        _ = try await IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "s1")],
            embedder: embedder,
            store: store
        ).run()
        let query = QueryService(embedder: embedder, store: store)

        let cases: [(query: String, expected: String)] = [
            ("MnemeQueryFacade", "api.md"),
            ("managed markdown memory", "memory.md"),
            ("研究方法", "cn.md")
        ]

        var vectorRankings: [(ranked: [String], relevant: Set<String>)] = []
        var hybridRankings: [(ranked: [String], relevant: Set<String>)] = []
        for testCase in cases {
            let vector = try await query.search(testCase.query, topK: 3, mode: .vector)
            let hybrid = try await query.search(testCase.query, topK: 3, mode: .hybrid)
            vectorRankings.append((ranked: vector.map { $0.uri.lastPathComponent }, relevant: [testCase.expected]))
            hybridRankings.append((ranked: hybrid.map { $0.uri.lastPathComponent }, relevant: [testCase.expected]))
        }

        let vectorAggregate = RetrievalEval.aggregate(vectorRankings, k: 3)
        let hybridAggregate = RetrievalEval.aggregate(hybridRankings, k: 3)
        XCTAssertGreaterThanOrEqual(hybridAggregate.hitAtK, vectorAggregate.hitAtK)
        XCTAssertGreaterThanOrEqual(hybridAggregate.mrr, vectorAggregate.mrr)
    }

    private func loadEvalCases() throws -> [(query: String, expected: String)] {
        let packageFixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("eval/queries.jsonl")
        let url = FileManager.default.fileExists(atPath: packageFixture.path)
            ? packageFixture
            : try XCTUnwrap(Bundle.module.url(
                forResource: "queries",
                withExtension: "jsonl",
                subdirectory: "Fixtures/eval"
            ))
        let content = try String(contentsOf: url, encoding: .utf8)
        return try content
            .split(separator: "\n")
            .map { line in
                let data = Data(line.utf8)
                let decoded = try JSONDecoder().decode(EvalQueryCase.self, from: data)
                return (decoded.query, decoded.expected)
            }
    }
}

private struct EvalQueryCase: Decodable {
    let query: String
    let expected: String
}
