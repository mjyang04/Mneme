import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor MLXLocalTextGenerator {
    private let modelDirectory: URL
    private var container: ModelContainer?
    private var allowsModelDownload: Bool

    init(modelDirectory: URL, allowsModelDownload: Bool = false) {
        self.modelDirectory = modelDirectory
        self.allowsModelDownload = allowsModelDownload
    }

    func setAllowsModelDownload(_ enabled: Bool) {
        allowsModelDownload = enabled
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

        let loaded: ModelContainer
        if let localModelDirectory = Self.localModelDirectory(root: modelDirectory) {
            loaded = try await loadModelContainer(
                from: localModelDirectory,
                using: #huggingFaceTokenizerLoader()
            )
        } else {
            guard allowsModelDownload else {
                throw MLXLocalTextGeneratorError.missingLocalModel(modelDirectory.path)
            }

            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            let hub = HubClient(cache: HubCache(cacheDirectory: modelDirectory))
            loaded = try await loadModelContainer(
                from: #hubDownloader(hub),
                using: #huggingFaceTokenizerLoader(),
                configuration: LLMRegistry.qwen3_0_6b_4bit
            )
        }
        container = loaded
        return loaded
    }

    private static func localModelDirectory(root: URL) -> URL? {
        if isLoadableModelDirectory(root) {
            return root
        }

        let snapshots = root
            .appendingPathComponent("models--mlx-community--Qwen3-0.6B-4bit", isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents
            .filter { isLoadableModelDirectory($0) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    private static func isLoadableModelDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            return false
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return contents.contains { $0.pathExtension == "safetensors" }
            && contents.contains { $0.lastPathComponent == "tokenizer.json" || $0.lastPathComponent == "tokenizer_config.json" }
    }

    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MLXLocalTextGeneratorError: LocalizedError {
    case missingLocalModel(String)

    var errorDescription: String? {
        switch self {
        case let .missingLocalModel(path):
            "MLX 模型尚未在本机准备好。请先在设置中明确允许首次下载，或把 Qwen3-0.6B-4bit 模型放到 \(path)。"
        }
    }
}
