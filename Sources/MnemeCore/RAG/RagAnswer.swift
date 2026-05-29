import Foundation

public struct RagAnswer: Equatable, Sendable {
    public let text: String
    public let citations: [SearchHit]

    public init(text: String, citations: [SearchHit]) {
        self.text = text
        self.citations = citations
    }
}
