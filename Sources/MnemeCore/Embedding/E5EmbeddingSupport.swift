import Foundation

public struct E5Input: Equatable, Sendable {
    public static let defaultMaxTokenCount = 512

    public let tokenIds: [Int]
    public let attentionMask: [Int]
    public let tokenTypeIds: [Int]
    public let positionIds: [Int]

    public init(tokenIds: [Int], maxTokenCount: Int = Self.defaultMaxTokenCount) {
        let trimmed = Array(tokenIds.prefix(maxTokenCount))
        self.tokenIds = trimmed
        self.attentionMask = [Int](repeating: 1, count: trimmed.count)
        self.tokenTypeIds = [Int](repeating: 0, count: trimmed.count)
        self.positionIds = trimmed.indices.map { $0 + 2 }
    }

    public static func preprocessedText(_ text: String, kind: EmbedKind) -> String {
        switch kind {
        case .query:
            "query: \(text)"
        case .passage:
            "passage: \(text)"
        }
    }
}

public struct CoreMLE5Resources: Equatable, Sendable {
    public let modelURL: URL
    public let tokenizerDirectoryURL: URL

    public init(modelURL: URL, tokenizerDirectoryURL: URL) {
        self.modelURL = modelURL
        self.tokenizerDirectoryURL = tokenizerDirectoryURL
    }
}

public struct CoreMLE5ResourceLocator: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func locate() throws -> CoreMLE5Resources {
        let modelURL = root.appendingPathComponent("multilingual-e5-small.mlpackage", isDirectory: true)
        let tokenizerDirectoryURL = root.appendingPathComponent("e5-tokenizer", isDirectory: true)
        let tokenizerJSONURL = tokenizerDirectoryURL.appendingPathComponent("tokenizer.json")
        let tokenizerConfigURL = tokenizerDirectoryURL.appendingPathComponent("tokenizer_config.json")

        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: tokenizerJSONURL.path),
              FileManager.default.fileExists(atPath: tokenizerConfigURL.path) else {
            throw EmbeddingError.modelUnavailable
        }

        return CoreMLE5Resources(
            modelURL: modelURL.standardizedFileURL,
            tokenizerDirectoryURL: tokenizerDirectoryURL.standardizedFileURL
        )
    }
}
