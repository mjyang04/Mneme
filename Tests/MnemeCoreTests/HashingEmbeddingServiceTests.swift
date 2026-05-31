import XCTest
@testable import MnemeCore

final class HashingEmbeddingServiceTests: XCTestCase {
    func test_dimensionAndCount() async throws {
        let service = HashingEmbeddingService(dimension: 64)
        let vectors = try await service.embed(["abc", "def"], kind: .passage)
        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0].count, 64)
    }

    func test_deterministic() async throws {
        let service = HashingEmbeddingService(dimension: 64)
        let first = try await service.embed(["hello world"], kind: .query)
        let second = try await service.embed(["hello world"], kind: .query)
        XCTAssertEqual(first[0], second[0])
    }

    func test_normalized() async throws {
        let service = HashingEmbeddingService(dimension: 64)
        let vector = try await service.embed(["some longer text here"], kind: .passage)[0]
        XCTAssertEqual(Vector.l2norm(vector), 1.0, accuracy: 1e-4)
    }

    func test_similarTextsCloserThanDissimilar() async throws {
        let service = HashingEmbeddingService(dimension: 512)
        let cat = try await service.embed(["the cat sat on the mat"], kind: .passage)[0]
        let cat2 = try await service.embed(["a cat sat on a mat today"], kind: .passage)[0]
        let other = try await service.embed(["quantum chromodynamics lattice"], kind: .passage)[0]
        XCTAssertGreaterThan(Vector.dot(cat, cat2), Vector.dot(cat, other))
    }
}
