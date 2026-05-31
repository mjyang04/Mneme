@testable import MnemeCore

actor SpyEmbeddingService: EmbeddingService {
    private let base: any EmbeddingService
    let id: String
    let dimension: Int
    private(set) var totalTextsEmbedded = 0

    init(base: any EmbeddingService) {
        self.base = base
        self.id = base.id
        self.dimension = base.dimension
    }

    func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        totalTextsEmbedded += texts.count
        return try await base.embed(texts, kind: kind)
    }
}
