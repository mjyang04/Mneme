import XCTest
@testable import MnemeCore

final class RagServiceTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RagVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "Mneme indexes local research notes, PDFs, code, transcripts, and activity logs."
            .write(to: vault.appendingPathComponent("mneme.md"), atomically: true, encoding: .utf8)
        try "The application keeps all search and answer generation fully offline on the Mac."
            .write(to: vault.appendingPathComponent("privacy.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func test_answer_returnsCitationsFromSearchHits() async throws {
        let query = try await makeIndexedQuery()
        let answer = try await query.answer("What does Mneme index?", topK: 2)

        XCTAssertFalse(answer.text.isEmpty)
        XCTAssertFalse(answer.citations.isEmpty)
        XCTAssertTrue(answer.text.contains("[1]"))
        XCTAssertTrue(answer.citations.allSatisfy { $0.kind == .notes })
        XCTAssertTrue(answer.citations.contains { $0.uri.lastPathComponent == "mneme.md" })
    }

    func test_answer_withoutEvidence_saysUnknownAndHasNoCitations() async throws {
        let embedder = HashingEmbeddingService(dimension: 128)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
        let query = QueryService(embedder: embedder, store: store)

        let answer = try await query.answer("What is Mneme?", topK: 3)

        XCTAssertTrue(answer.text.contains("不知道"))
        XCTAssertTrue(answer.citations.isEmpty)
    }

    func test_extractiveGenerator_limitsSnippetLengthAndNumbersCitations() async throws {
        let hit = SearchHit(
            chunkId: "doc#0",
            documentId: "doc",
            score: 0.9,
            text: String(repeating: "a", count: 500),
            title: "Doc",
            uri: URL(fileURLWithPath: "/tmp/doc.md"),
            kind: .notes,
            locator: nil
        )
        let generator = ExtractiveRagAnswerGenerator(maxSnippetCharacters: 80)

        let text = try await generator.answer(question: "Question?", citations: [hit])

        XCTAssertTrue(text.contains("[1]"))
        XCTAssertLessThan(text.count, 260)
    }

    func test_promptBuilderIncludesEvidenceAndCitationNumbers() {
        let hit = SearchHit(
            chunkId: "c1",
            documentId: "d1",
            score: 0.9,
            text: "Mneme keeps files local.",
            title: "Privacy Note",
            uri: URL(fileURLWithPath: "/tmp/privacy.md"),
            kind: .notes,
            locator: nil
        )

        let prompt = RagPromptBuilder.prompt(question: "Where is data stored?", citations: [hit])

        XCTAssertTrue(prompt.contains("仅依据【资料】回答"))
        XCTAssertTrue(prompt.contains("[1]"), prompt)
        XCTAssertTrue(prompt.contains("Privacy Note"))
        XCTAssertTrue(prompt.contains("Mneme keeps files local."))
        XCTAssertTrue(prompt.contains("Where is data stored?"))
    }

    func test_answerStream_yieldsIncrementalAnswersWithCitations() async throws {
        let embedder = HashingEmbeddingService(dimension: 512)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
        let pipeline = IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "notes")],
            embedder: embedder,
            store: store
        )
        _ = try await pipeline.run()
        let query = QueryService(
            embedder: embedder,
            store: store,
            ragAnswerGenerator: StreamingTestRagAnswerGenerator()
        )

        var partials: [RagAnswer] = []
        for try await partial in query.answerStream("What does Mneme index?", topK: 2) {
            partials.append(partial)
        }

        XCTAssertEqual(partials.map(\.text), ["first ", "first second"])
        XCTAssertFalse(partials.last?.citations.isEmpty ?? true)
    }

    private func makeIndexedQuery() async throws -> QueryService {
        let embedder = HashingEmbeddingService(dimension: 512)
        let store = try IndexStore(path: nil, embedderId: embedder.id, dimension: embedder.dimension)
        let pipeline = IndexingPipeline(
            connectors: [NotesConnector(root: vault, sourceId: "notes")],
            embedder: embedder,
            store: store
        )
        _ = try await pipeline.run()
        return QueryService(embedder: embedder, store: store)
    }
}

private struct StreamingTestRagAnswerGenerator: RagAnswerGenerator {
    func answer(question: String, citations: [SearchHit]) async throws -> String {
        "first second"
    }

    func answerStream(question: String, citations: [SearchHit]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("first ")
            continuation.yield("second")
            continuation.finish()
        }
    }
}
