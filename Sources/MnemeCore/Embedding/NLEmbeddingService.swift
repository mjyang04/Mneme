import Foundation
@preconcurrency import NaturalLanguage

public struct NLEmbeddingService: EmbeddingService {
    public let id: String
    public let dimension: Int
    private let embedding: NLEmbedding

    public init(language: NLLanguage = .english) throws {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            throw EmbeddingError.modelUnavailable
        }
        self.id = "nl-sentence-\(language.rawValue)-v1"
        self.embedding = embedding
        self.dimension = embedding.dimension
    }

    public func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        texts.map { text in
            guard let vector = embedding.vector(for: text) else {
                return [Float](repeating: 0, count: dimension)
            }
            return Vector.normalize(vector.map(Float.init))
        }
    }
}
