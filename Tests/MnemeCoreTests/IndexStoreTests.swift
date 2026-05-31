import XCTest
@testable import MnemeCore

final class IndexStoreTests: XCTestCase {
    private func tempPath() -> String {
        NSTemporaryDirectory() + "mneme-test-\(UUID().uuidString).sqlite"
    }

    private func upsertDoc(
        _ store: IndexStore,
        id: String,
        kind: SourceKind,
        hash: String,
        vector: [Float]
    ) async throws {
        try await store.upsert(
            documentId: id,
            sourceId: "s1",
            kind: kind,
            uri: URL(fileURLWithPath: "/tmp/\(id).md"),
            title: id,
            contentHash: hash,
            chunks: [Chunk(
                ordinal: 0,
                text: "text of \(id)",
                locator: TextLocator(startChar: 0, endChar: 5)
            )],
            vectors: [vector]
        )
    }

    func test_upsertAndSearch_returnsClosest() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await upsertDoc(store, id: "B", kind: .notes, hash: "h2", vector: [0, 1, 0])

        let hits = try await store.search([0.9, 0.1, 0], topK: 1, filter: nil)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].documentId, "A")
        XCTAssertEqual(hits[0].kind, .notes)
    }

    func test_incrementalUpsert_isIdempotent() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])

        let count = try await store.documentCount()
        let hash = try await store.documentHash(id: "A")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(hash, "h1")
    }

    func test_deleteDocument_cascades() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await store.deleteDocument(id: "A")

        let hits = try await store.search([1, 0, 0], topK: 5, filter: nil)
        let hash = try await store.documentHash(id: "A")
        XCTAssertTrue(hits.isEmpty)
        XCTAssertNil(hash)
    }

    func test_filterByKind() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        try await upsertDoc(store, id: "B", kind: .pdf, hash: "h2", vector: [1, 0, 0])

        let hits = try await store.search(
            [1, 0, 0],
            topK: 5,
            filter: SearchFilter(kinds: [.pdf])
        )
        XCTAssertEqual(hits.map(\.documentId), ["B"])
    }

    func test_searchLexical_returnsFTSMatchesIncludingCJKBigramText() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await store.upsert(
            documentId: "CJK",
            sourceId: "s1",
            kind: .notes,
            uri: URL(fileURLWithPath: "/tmp/cjk.md"),
            title: "CJK",
            contentHash: "h1",
            chunks: [Chunk(ordinal: 0, text: "本地研究方法 and exactkeyword", locator: TextLocator())],
            vectors: [[1, 0, 0]]
        )

        let english = try await store.searchLexical(FtsQueryBuilder.build("exactkeyword"), topK: 5)
        XCTAssertEqual(english.map(\.documentId), ["CJK"])

        let cjk = try await store.searchLexical(FtsQueryBuilder.build("研究方法"), topK: 5)
        XCTAssertEqual(cjk.map(\.documentId), ["CJK"])
    }

    func test_upsertPersistsDocumentMetadataInSearchHits() async throws {
        let store = try IndexStore(path: nil, embedderId: "t", dimension: 3)
        try await store.upsert(
            documentId: "web",
            sourceId: "s1",
            kind: .web,
            uri: URL(fileURLWithPath: "/tmp/clip.html"),
            title: "Clip",
            contentHash: "h1",
            meta: ["source_url": "https://example.com/article"],
            chunks: [Chunk(ordinal: 0, text: "exact metadata keyword", locator: TextLocator())],
            vectors: [[1, 0, 0]]
        )

        let vectorHits = try await store.search([1, 0, 0], topK: 5)
        XCTAssertEqual(vectorHits.first?.meta["source_url"], "https://example.com/article")

        let lexicalHits = try await store.searchLexical(FtsQueryBuilder.build("metadata"), topK: 5)
        let storedMeta = try await store.documentMeta(id: "web")
        XCTAssertEqual(lexicalHits.first?.meta["source_url"], "https://example.com/article")
        XCTAssertEqual(storedMeta?["source_url"], "https://example.com/article")
    }

    func test_configMismatch_throws() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = try IndexStore(path: path, embedderId: "a", dimension: 3)
        try await upsertDoc(store, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])

        XCTAssertThrowsError(try IndexStore(path: path, embedderId: "b", dimension: 3))
    }

    func test_readOnlyStore_canSearchExistingIndexButCannotWrite() async throws {
        let path = tempPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }

        let writer = try IndexStore(path: path, embedderId: "t", dimension: 3)
        try await upsertDoc(writer, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])

        let config = try IndexStore.readConfig(path: path)
        XCTAssertEqual(config, IndexStoreConfig(embedderId: "t", dimension: 3))

        let reader = try IndexStore(readonlyPath: path, embedderId: "t", dimension: 3)
        let hits = try await reader.search([1, 0, 0], topK: 5, filter: nil)
        XCTAssertEqual(hits.map(\.documentId), ["A"])

        do {
            try await reader.deleteDocument(id: "A")
            XCTFail("Read-only store should reject deletes")
        } catch {
            // Expected.
        }
    }

    func test_readOnlyStore_rejectsMissingOrMismatchedIndex() async throws {
        let path = tempPath()
        XCTAssertThrowsError(try IndexStore(readonlyPath: path, embedderId: "t", dimension: 3))

        let writer = try IndexStore(path: path, embedderId: "t", dimension: 3)
        try await upsertDoc(writer, id: "A", kind: .notes, hash: "h1", vector: [1, 0, 0])
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }

        XCTAssertThrowsError(try IndexStore(readonlyPath: path, embedderId: "other", dimension: 3))
    }
}
