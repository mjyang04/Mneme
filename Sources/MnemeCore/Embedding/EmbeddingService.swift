import Foundation

public enum EmbedKind: Sendable {
    case query
    case passage
}

public enum EmbeddingError: Error, Equatable {
    case modelUnavailable
    case dimensionMismatch
}

public protocol EmbeddingService: Sendable {
    var id: String { get }
    var dimension: Int { get }

    func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]]
}
