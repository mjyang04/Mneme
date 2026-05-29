import Foundation

public protocol RagAnswerGenerator: Sendable {
    func answer(question: String, citations: [SearchHit]) async throws -> String
    func answerStream(question: String, citations: [SearchHit]) -> AsyncThrowingStream<String, Error>
}

public extension RagAnswerGenerator {
    func answerStream(question: String, citations: [SearchHit]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await answer(question: question, citations: citations)
                    if !text.isEmpty {
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
