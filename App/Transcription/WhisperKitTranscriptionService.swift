import Foundation
import MnemeCore
@preconcurrency import WhisperKit

final class WhisperKitTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let modelDirectory: URL

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func transcribe(_ audio: URL, options: TranscribeOptions) -> AsyncThrowingStream<TranscriptSegment, Error> {
        let setupError: Error?
        let resolvedModelFolder: String?
        do {
            try FileManager.default.createDirectory(
                at: modelDirectory,
                withIntermediateDirectories: true
            )
            if options.allowsModelDownload {
                resolvedModelFolder = nil
                setupError = nil
            } else if let localModelFolder = Self.localModelFolder(root: modelDirectory, model: options.model) {
                resolvedModelFolder = localModelFolder.path
                setupError = nil
            } else {
                resolvedModelFolder = nil
                setupError = WhisperKitTranscriptionError.missingLocalModel(options.model, modelDirectory.path)
            }
        } catch {
            resolvedModelFolder = nil
            setupError = error
        }

        return AsyncThrowingStream<TranscriptSegment, Error> { continuation in
            if let setupError {
                continuation.finish(throwing: setupError)
                return
            }
            let modelDirectory = self.modelDirectory
            Task.detached(priority: .utility) {
                do {
                    let config = WhisperKitConfig(
                        model: options.model,
                        downloadBase: modelDirectory,
                        modelFolder: resolvedModelFolder,
                        verbose: false,
                        logLevel: .error,
                        prewarm: false,
                        download: options.allowsModelDownload
                    )
                    let whisperKit = try await WhisperKit(config)
                    let decodingOptions = DecodingOptions(
                        verbose: false,
                        language: options.language,
                        skipSpecialTokens: true,
                        withoutTimestamps: false
                    )
                    let results = try await whisperKit.transcribe(
                        audioPath: audio.path,
                        decodeOptions: decodingOptions
                    )

                    for segment in Self.segments(from: results) {
                        continuation.yield(segment)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func segments(from results: [TranscriptionResult]) -> [TranscriptSegment] {
        let segmentResults = results.flatMap { result in
            result.segments.map { segment in
                TranscriptSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: TranscriptTextCleaner.clean(segment.text)
                )
            }
        }
        if !segmentResults.isEmpty {
            return segmentResults
        }

        return results.enumerated().compactMap { index, result in
            let text = TranscriptTextCleaner.clean(result.text)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(start: TimeInterval(index), end: TimeInterval(index + 1), text: text)
        }
    }

    private static func localModelFolder(root: URL, model: String) -> URL? {
        let normalizedModel = model.hasPrefix("openai_whisper-") ? model : "openai_whisper-\(model)"
        let candidate = root
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(normalizedModel, isDirectory: true)
        guard FileManager.default.fileExists(atPath: candidate.appendingPathComponent("MelSpectrogram.mlmodelc").path) else {
            return nil
        }
        return candidate
    }
}

private enum WhisperKitTranscriptionError: LocalizedError {
    case missingLocalModel(String, String)

    var errorDescription: String? {
        switch self {
        case let .missingLocalModel(model, directory):
            "WhisperKit model '\(model)' is not installed under \(directory). Enable first-time model download or copy the model assets into that directory."
        }
    }
}
