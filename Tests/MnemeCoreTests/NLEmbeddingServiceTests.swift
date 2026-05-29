import XCTest
@testable import MnemeCore

final class NLEmbeddingServiceTests: XCTestCase {
    private func makeService() throws -> NLEmbeddingService {
        do {
            return try NLEmbeddingService()
        } catch {
            throw XCTSkip("System NaturalLanguage sentence embedding model is unavailable.")
        }
    }

    func test_dimensionPositive_andNormalized() async throws {
        let service = try makeService()
        XCTAssertGreaterThan(service.dimension, 0)
        let vector = try await service.embed(["machine learning"], kind: .passage)[0]
        XCTAssertEqual(vector.count, service.dimension)
        XCTAssertEqual(Vector.l2norm(vector), 1.0, accuracy: 1e-3)
    }

    func test_emptyString_zeroVector() async throws {
        let service = try makeService()
        let vector = try await service.embed([""], kind: .passage)[0]
        XCTAssertEqual(Vector.l2norm(vector), 0.0, accuracy: 1e-6)
    }

    func test_semanticOrdering() async throws {
        let service = try makeService()
        let dog = try await service.embed(["dog"], kind: .query)[0]
        let puppy = try await service.embed(["puppy"], kind: .passage)[0]
        let econ = try await service.embed(["macroeconomic policy"], kind: .passage)[0]
        XCTAssertGreaterThan(Vector.dot(dog, puppy), Vector.dot(dog, econ))
    }
}
