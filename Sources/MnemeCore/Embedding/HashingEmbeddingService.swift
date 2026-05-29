import Foundation

public struct HashingEmbeddingService: EmbeddingService {
    public let id: String
    public let dimension: Int

    public init(dimension: Int = 256) {
        self.id = "hashing-v1-d\(dimension)"
        self.dimension = dimension
    }

    public func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        texts.map(embedOne)
    }

    private func embedOne(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        let characters = Array(text.lowercased())

        if characters.count >= 3 {
            for index in 0...(characters.count - 3) {
                let gram = String(characters[index..<(index + 3)])
                let bucket = Int(Vector.fnv1a(gram) % UInt32(dimension))
                vector[bucket] += 1
            }
        } else if !characters.isEmpty {
            let bucket = Int(Vector.fnv1a(String(characters)) % UInt32(dimension))
            vector[bucket] += 1
        }

        return Vector.normalize(vector)
    }
}
