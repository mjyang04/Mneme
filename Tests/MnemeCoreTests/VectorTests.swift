import XCTest
@testable import MnemeCore

final class VectorTests: XCTestCase {
    func test_normalize_unitLength() {
        let vector = Vector.normalize([3, 4])
        XCTAssertEqual(Vector.l2norm(vector), 1.0, accuracy: 1e-5)
    }

    func test_normalize_zeroStaysZero() {
        XCTAssertEqual(Vector.normalize([0, 0]), [0, 0])
    }

    func test_dotProduct_ofNormalizedEquals1ForSame() {
        let vector = Vector.normalize([1, 2, 3])
        XCTAssertEqual(Vector.dot(vector, vector), 1.0, accuracy: 1e-5)
    }

    func test_dataRoundTrip() {
        let vector: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual([Float](data: vector.data), vector)
    }
}
