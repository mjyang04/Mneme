import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor MLXLocalTextGenerator {
    private let modelDirectory: URL
    private var container: ModelContainer?

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func respond(
        prompt: String,
        instructions: String,
        maxTokens: Int,
        temperature: Float = 0.2,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.05
    ) async throws -> String {
        let container = try await modelContainer()
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty
            ),
            additionalContext: ["enable_thinking": false]
        )
        return try await session.respond(to: prompt)
    }

    nonisolated func stream(
        prompt: String,
        instructions: String,
        maxTokens: Int,
        temperature: Float = 0.2,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.05
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let container = try await modelContainer()
                    let session = ChatSession(
                        container,
                        instructions: instructions,
                        generateParameters: GenerateParameters(
                            maxTokens: maxTokens,
                            temperature: temperature,
                            topP: topP,
                            repetitionPenalty: repetitionPenalty
                        ),
                        additionalContext: ["enable_thinking": false]
                    )
                    for try await chunk in session.streamResponse(to: prompt) {
                        if !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func modelContainer() async throws -> ModelContainer {
        if let container {
            return container
        }

        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let hub = HubClient(cache: HubCache(cacheDirectory: modelDirectory))
        let loaded = try await loadModelContainer(
            from: #hubDownloader(hub),
            using: #huggingFaceTokenizerLoader(),
            configuration: LLMRegistry.qwen3_0_6b_4bit
        )
        container = loaded
        return loaded
    }

    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
