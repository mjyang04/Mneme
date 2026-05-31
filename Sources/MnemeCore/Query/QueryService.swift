import Foundation

public struct QueryService: Sendable {
    private let embedder: any EmbeddingService
    private let store: IndexStore
    private let ragAnswerGenerator: any RagAnswerGenerator

    public init(
        embedder: any EmbeddingService,
        store: IndexStore,
        ragAnswerGenerator: any RagAnswerGenerator = ExtractiveRagAnswerGenerator()
    ) {
        self.embedder = embedder
        self.store = store
        self.ragAnswerGenerator = ragAnswerGenerator
    }

    public func search(
        _ text: String,
        topK: Int = 20,
        mode: SearchMode = .hybrid,
        filter: SearchFilter? = nil
    ) async throws -> [SearchHit] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let queryVector = try await embedder.embed([trimmed], kind: .query)[0]
        let vectorHits = try await store.search(queryVector, topK: topK * Self.rankInflation, filter: filter)
        guard mode == .hybrid else {
            return Self.collapseByDocument(vectorHits, topK: topK)
        }

        let ftsQuery = FtsQueryBuilder.build(trimmed)
        let lexicalHits: [SearchHit]
        if ftsQuery.isEmpty {
            lexicalHits = []
        } else {
            do {
                lexicalHits = try await store.searchLexical(
                    ftsQuery,
                    topK: topK * Self.rankInflation,
                    filter: filter
                )
            } catch {
                Self.reportLexicalSearchFailure(error)
                lexicalHits = []
            }
        }
        let raw = RankFusion.rrf([vectorHits, lexicalHits])
        return Self.collapseByDocument(raw, topK: topK)
    }

    public func answer(
        _ question: String,
        topK: Int = 8,
        mode: SearchMode = .hybrid,
        filter: SearchFilter? = nil
    ) async throws -> RagAnswer {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return RagAnswer(text: "", citations: [])
        }

        let citations = try await search(trimmed, topK: topK, mode: mode, filter: filter)
        let text = try await ragAnswerGenerator.answer(question: trimmed, citations: citations)
        return RagAnswer(text: text, citations: citations)
    }

    public func answerStream(
        _ question: String,
        topK: Int = 8,
        mode: SearchMode = .hybrid,
        filter: SearchFilter? = nil
    ) -> AsyncThrowingStream<RagAnswer, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        continuation.yield(RagAnswer(text: "", citations: []))
                        continuation.finish()
                        return
                    }

                    let citations = try await search(trimmed, topK: topK, mode: mode, filter: filter)
                    var text = ""
                    for try await chunk in ragAnswerGenerator.answerStream(question: trimmed, citations: citations) {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }
                        text += chunk
                        continuation.yield(RagAnswer(text: text, citations: citations))
                    }
                    if text.isEmpty {
                        continuation.yield(RagAnswer(text: "", citations: citations))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static let rankInflation = 4

    private static func reportLexicalSearchFailure(_ error: Error) {
        let message = "mneme: lexical search failed; falling back to vector search: \(error.localizedDescription)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    static func collapseByDocument(_ hits: [SearchHit], topK: Int) -> [SearchHit] {
        var bestByDocument: [String: SearchHit] = [:]
        for hit in hits {
            if let current = bestByDocument[hit.documentId], current.score >= hit.score {
                continue
            }
            bestByDocument[hit.documentId] = hit
        }
        return Array(bestByDocument.values.sorted { $0.score > $1.score }.prefix(topK))
    }
}
