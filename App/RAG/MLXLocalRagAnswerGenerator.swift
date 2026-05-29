import Foundation
import MnemeCore

actor MLXLocalRagAnswerGenerator: RagAnswerGenerator {
    private let textGenerator: MLXLocalTextGenerator
    private let maxTokens: Int

    init(textGenerator: MLXLocalTextGenerator, maxTokens: Int = 512) {
        self.textGenerator = textGenerator
        self.maxTokens = maxTokens
    }

    init(modelDirectory: URL, maxTokens: Int = 512) {
        self.textGenerator = MLXLocalTextGenerator(modelDirectory: modelDirectory)
        self.maxTokens = maxTokens
    }

    func answer(question: String, citations: [SearchHit]) async throws -> String {
        guard !citations.isEmpty else {
            return "不知道：当前索引没有找到可引用的资料。"
        }

        let answer = try await textGenerator.respond(
            prompt: RagPromptBuilder.prompt(question: question, citations: citations),
            instructions: "Only return the final answer. Do not include hidden reasoning, chain-of-thought, or <think> blocks.",
            maxTokens: maxTokens
        )
        return MLXLocalTextGenerator.clean(answer)
    }

    nonisolated func answerStream(question: String, citations: [SearchHit]) -> AsyncThrowingStream<String, Error> {
        guard !citations.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.yield("不知道：当前索引没有找到可引用的资料。")
                continuation.finish()
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                let prompt = RagPromptBuilder.prompt(question: question, citations: citations)
                var raw = ""
                var emitted = ""
                do {
                    for try await chunk in textGenerator.stream(
                        prompt: prompt,
                        instructions: "Only return the final answer. Do not include hidden reasoning, chain-of-thought, or <think> blocks.",
                        maxTokens: maxTokens
                    ) {
                        raw += chunk
                        let cleaned = MLXLocalTextGenerator.clean(raw)
                        guard cleaned.count > emitted.count,
                              cleaned.hasPrefix(emitted) else {
                            continue
                        }
                        let delta = String(cleaned.dropFirst(emitted.count))
                        emitted = cleaned
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

struct ResilientRagAnswerGenerator: RagAnswerGenerator {
    let primary: any RagAnswerGenerator
    let fallback: ExtractiveRagAnswerGenerator

    init(primary: any RagAnswerGenerator, fallback: ExtractiveRagAnswerGenerator = ExtractiveRagAnswerGenerator()) {
        self.primary = primary
        self.fallback = fallback
    }

    func answer(question: String, citations: [SearchHit]) async throws -> String {
        do {
            return try await primary.answer(question: question, citations: citations)
        } catch {
            let extractive = try await fallback.answer(question: question, citations: citations)
            return """
            \(extractive)

            MLX 本地生成暂不可用：\(error.localizedDescription)
            """
        }
    }

    func answerStream(question: String, citations: [SearchHit]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var yielded = false
                do {
                    for try await chunk in primary.answerStream(question: question, citations: citations) {
                        yielded = true
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    do {
                        let extractive = try await fallback.answer(question: question, citations: citations)
                        if yielded {
                            continuation.yield("\n\nMLX 本地生成中断，以下是 fallback 摘录：\n\(extractive)")
                        } else {
                            continuation.yield("""
                            \(extractive)

                            MLX 本地生成暂不可用：\(error.localizedDescription)
                            """)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    continuation.finish()
                }
            }
        }
    }
}
