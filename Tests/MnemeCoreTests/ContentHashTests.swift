import XCTest
@testable import MnemeCore

final class ContentHashTests: XCTestCase {
    func test_isDeterministic() {
        XCTAssertEqual(ContentHash.of("hello"), ContentHash.of("hello"))
    }

    func test_differsForDifferentInput() {
        XCTAssertNotEqual(ContentHash.of("hello"), ContentHash.of("world"))
    }

    func test_is16HexChars() {
        let hash = ContentHash.of("anything")
        XCTAssertEqual(hash.count, 16)
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
