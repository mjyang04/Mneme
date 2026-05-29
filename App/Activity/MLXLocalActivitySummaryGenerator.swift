import Foundation
import MnemeCore

actor MLXLocalActivitySummaryGenerator: ActivitySummaryGenerator {
    private let textGenerator: MLXLocalTextGenerator
    private let maxTokens: Int

    init(textGenerator: MLXLocalTextGenerator, maxTokens: Int = 160) {
        self.textGenerator = textGenerator
        self.maxTokens = maxTokens
    }

    init(modelDirectory: URL, maxTokens: Int = 160) {
        self.textGenerator = MLXLocalTextGenerator(modelDirectory: modelDirectory)
        self.maxTokens = maxTokens
    }

    func summarize(_ activity: DailyActivity) async throws -> String {
        let answer = try await textGenerator.respond(
            prompt: ActivitySummaryPromptBuilder().prompt(for: activity),
            instructions: "Only return the final activity summary. Do not include hidden reasoning, chain-of-thought, citations, or <think> blocks.",
            maxTokens: maxTokens,
            temperature: 0.2,
            topP: 0.9,
            repetitionPenalty: 1.05
        )
        return MLXLocalTextGenerator.clean(answer)
    }
}
