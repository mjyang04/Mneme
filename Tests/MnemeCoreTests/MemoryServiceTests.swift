import XCTest
@testable import MnemeCore

final class MemoryServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mneme-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_memoryStoreWritesStableDedupedMarkdown() throws {
        let store = MemoryStore(directory: directory)
        let input = RememberInputDTO(
            text: "Remember that Mneme V2 exposes a local MCP server.",
            tags: ["v2", "agent"],
            sourceRef: "doc#1",
            link: "mneme://test",
            title: "V2 MCP"
        )

        let first = try store.write(input, now: Date(timeIntervalSince1970: 0))
        let second = try store.write(input, now: Date(timeIntervalSince1970: 10))

        XCTAssertFalse(first.deduped)
        XCTAssertTrue(second.deduped)
        XCTAssertEqual(first.key, second.key)
        let markdown = try String(contentsOf: first.url, encoding: .utf8)
        XCTAssertTrue(markdown.contains("type: mneme-memory"))
        XCTAssertTrue(markdown.contains("title: \"V2 MCP\""))
        XCTAssertTrue(markdown.contains("Remember that Mneme V2 exposes a local MCP server."))
    }

    func test_memoryServiceIndexesWrittenMemory() async throws {
        let embedder = HashingEmbeddingService(dimension: 32)
        let indexPath = directory.appendingPathComponent("index.sqlite").path
        let index = try IndexStore(path: indexPath, embedderId: embedder.id, dimension: embedder.dimension)
        let pipeline = IndexingPipeline(connectors: [], embedder: embedder, store: index)
        let service = MemoryService(
            memoryStore: MemoryStore(directory: directory.appendingPathComponent("Memory", isDirectory: true)),
            pipeline: pipeline
        )

        let result = try await service.remember(RememberInputDTO(
            text: "The standalone mneme command reads the local index.",
            tags: ["cli"],
            sourceRef: "test"
        ))
        XCTAssertFalse(result.deduped)
        XCTAssertTrue(result.indexed)

        let hits = try await index.search(
            try await embedder.embed(["standalone mneme command"], kind: .query)[0],
            topK: 5,
            filter: SearchFilter(kinds: [.memory])
        )
        XCTAssertEqual(hits.first?.kind, .memory)
        XCTAssertEqual(hits.first?.documentId, "memory://mem-\(result.key)")
    }

    func test_memoryConnectorParsesYamlListTags() throws {
        let markdown = """
        ---
        title: "Tagged Memory"
        tags:
          - "cli"
          - "agent"
        source_ref: "test"
        ---

        Remember local context.
        """

        let parsed = MemoryConnector.parse(markdown)
        XCTAssertEqual(parsed.title, "Tagged Memory")
        XCTAssertEqual(parsed.meta["tags"], "cli, agent")
        XCTAssertEqual(parsed.meta["source_ref"], "test")
        XCTAssertEqual(parsed.body, "Remember local context.")
    }
}
