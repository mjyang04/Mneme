import XCTest
@testable import MnemeCore

final class E5EmbeddingSupportTests: XCTestCase {
    func test_prefixedText_addsE5QueryAndPassagePrefixes() {
        XCTAssertEqual(E5Input.preprocessedText("privacy search", kind: .query), "query: privacy search")
        XCTAssertEqual(E5Input.preprocessedText("privacy search", kind: .passage), "passage: privacy search")
    }

    func test_trimmedTokenIds_truncatesToMaxLengthAndBuildsAttentionMask() {
        let input = E5Input(tokenIds: Array(1...600), maxTokenCount: 512)

        XCTAssertEqual(input.tokenIds.count, 512)
        XCTAssertEqual(input.tokenIds.first, 1)
        XCTAssertEqual(input.tokenIds.last, 512)
        XCTAssertEqual(input.attentionMask.count, 512)
        XCTAssertTrue(input.attentionMask.allSatisfy { $0 == 1 })
        XCTAssertEqual(input.tokenTypeIds.count, 512)
        XCTAssertTrue(input.tokenTypeIds.allSatisfy { $0 == 0 })
        XCTAssertEqual(input.positionIds.prefix(3), [2, 3, 4])
        XCTAssertEqual(input.positionIds.last, 513)
    }

    func test_resourceLocatorFindsModelAndTokenizerDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("E5Resources-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("multilingual-e5-small.mlpackage", isDirectory: true)
        let tokenizer = root.appendingPathComponent("e5-tokenizer", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try "{}".write(to: tokenizer.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: tokenizer.appendingPathComponent("tokenizer_config.json"), atomically: true, encoding: .utf8)

        let resources = try CoreMLE5ResourceLocator(root: root).locate()

        XCTAssertEqual(resources.modelURL, model)
        XCTAssertEqual(resources.tokenizerDirectoryURL, tokenizer)
    }

    func test_resourceLocatorThrowsWhenAnyRequiredResourceIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("E5Resources-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        XCTAssertThrowsError(try CoreMLE5ResourceLocator(root: root).locate()) { error in
            XCTAssertEqual(error as? EmbeddingError, .modelUnavailable)
        }
    }
}
