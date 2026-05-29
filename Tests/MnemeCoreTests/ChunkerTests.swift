import XCTest
@testable import MnemeCore

final class ChunkerTests: XCTestCase {
    func test_shortText_singleChunk() {
        let chunks = Chunker(targetChars: 100, overlapChars: 20).chunk("hello world")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].ordinal, 0)
        XCTAssertEqual(chunks[0].text, "hello world")
        XCTAssertEqual(chunks[0].locator, TextLocator(startChar: 0, endChar: 11))
    }

    func test_longText_splitsWithOverlap() {
        let paragraph = String(repeating: "a", count: 100)
        let text = [paragraph, paragraph, paragraph].joined(separator: "\n\n")
        let chunks = Chunker(targetChars: 120, overlapChars: 30).chunk(text)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.map(\.ordinal), Array(0..<chunks.count))
        XCTAssertEqual(chunks.last?.locator.endChar, text.count)
    }

    func test_emptyText_noChunks() {
        XCTAssertTrue(Chunker().chunk("   ").isEmpty)
    }
}
