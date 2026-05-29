import XCTest
@testable import MnemeCore

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(MnemeCore.version, "0.1.0")
    }
}
