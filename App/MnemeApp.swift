import Darwin
import Dispatch
import Foundation
import MnemeCore
import SwiftUI

@main
@MainActor
struct MnemeApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        if let audioPath = ProcessInfo.processInfo.environment["MNEME_TRANSCRIBE_DIAGNOSTIC_AUDIO"] {
            let model = ProcessInfo.processInfo.environment["MNEME_TRANSCRIBE_DIAGNOSTIC_MODEL"] ?? "tiny"
            let language = ProcessInfo.processInfo.environment["MNEME_TRANSCRIBE_DIAGNOSTIC_LANGUAGE"]
            let allowsDownload = ProcessInfo.processInfo.environment["MNEME_TRANSCRIBE_DIAGNOSTIC_DOWNLOAD"] == "1"
            let audio = URL(fileURLWithPath: audioPath)
            let appSupportDirectory = AppEnvironment.appSupportDir()
            let modelDirectory = appSupportDirectory.appendingPathComponent("Models/WhisperKit", isDirectory: true)
            print("transcription.models.dir=\(modelDirectory.path)")
            fflush(stdout)
            let transcriptionService = WhisperKitTranscriptionService(
                modelDirectory: modelDirectory
            )
            let options = TranscribeOptions(
                model: model,
                language: language?.isEmpty == true ? nil : language,
                allowsModelDownload: allowsDownload
            )
            Task.detached(priority: .utility) {
                do {
                    let segments = try await Self.collectTranscript(
                        service: transcriptionService,
                        audio: audio,
                        options: options
                    )
                    print("transcription.model=\(model)")
                    print("transcription.audio=\(audio.path)")
                    print("transcription.segments.count=\(segments.count)")
                    print("transcription.text=\(segments.map(\.text).joined(separator: " "))")
                    if segments.isEmpty {
                        fflush(stdout)
                        exit(4)
                    }
                    fflush(stdout)
                    exit(0)
                } catch {
                    print("transcription.error=\(error.localizedDescription)")
                    fflush(stdout)
                    exit(4)
                }
            }
            dispatchMain()
        }
        if ProcessInfo.processInfo.environment["MNEME_MLX_DIAGNOSTIC"] == "1" {
            let appSupportDirectory = AppEnvironment.appSupportDir()
            let modelDirectory = appSupportDirectory.appendingPathComponent("Models/MLX", isDirectory: true)
            let allowsDownload = ProcessInfo.processInfo.environment["MNEME_MLX_DIAGNOSTIC_DOWNLOAD"] == "1"
            print("mlx.models.dir=\(modelDirectory.path)")
            fflush(stdout)
            let textGenerator = MLXLocalTextGenerator(
                modelDirectory: modelDirectory,
                allowsModelDownload: allowsDownload
            )
            let generator = MLXLocalRagAnswerGenerator(textGenerator: textGenerator, maxTokens: 96)
            let question = ProcessInfo.processInfo.environment["MNEME_MLX_DIAGNOSTIC_QUESTION"]
                ?? "Where does Mneme keep research data?"
            let hit = SearchHit(
                chunkId: "diagnostic#0",
                documentId: "diagnostic",
                score: 1,
                text: "Mneme keeps research notes, transcripts, activity logs, search indexes, and model assets on the local Mac.",
                title: "Mneme Privacy Diagnostic",
                uri: URL(fileURLWithPath: "/private/tmp/mneme-privacy.md"),
                kind: .notes,
                locator: nil
            )
            Task.detached(priority: .utility) {
                do {
                    var answer = ""
                    var chunks = 0
                    for try await chunk in generator.answerStream(question: question, citations: [hit]) {
                        chunks += 1
                        answer += chunk
                    }
                    print("mlx.stream.chunks=\(chunks)")
                    print("mlx.answer=\(answer)")
                    fflush(stdout)
                    exit(chunks > 0 && answer.contains("[1]") && !answer.contains("<think>") ? 0 : 5)
                } catch {
                    print("mlx.error=\(error.localizedDescription)")
                    fflush(stdout)
                    exit(5)
                }
            }
            dispatchMain()
        }
        if ProcessInfo.processInfo.environment["MNEME_ACTIVITY_SUMMARY_DIAGNOSTIC"] == "1" {
            let appSupportDirectory = AppEnvironment.appSupportDir()
            let modelDirectory = appSupportDirectory.appendingPathComponent("Models/MLX", isDirectory: true)
            let allowsDownload = ProcessInfo.processInfo.environment["MNEME_MLX_DIAGNOSTIC_DOWNLOAD"] == "1"
                || ProcessInfo.processInfo.environment["MNEME_ACTIVITY_SUMMARY_DIAGNOSTIC_DOWNLOAD"] == "1"
            print("activity.summary.models.dir=\(modelDirectory.path)")
            fflush(stdout)
            let textGenerator = MLXLocalTextGenerator(
                modelDirectory: modelDirectory,
                allowsModelDownload: allowsDownload
            )
            let generator = ResilientActivitySummaryGenerator(
                primary: MLXLocalActivitySummaryGenerator(textGenerator: textGenerator, maxTokens: 96)
            )
            let activity = DailyActivity(day: "2026-05-29", projects: [
                ProjectActivity(
                    name: "Mneme",
                    rootPath: "/Users/mj/Mneme",
                    filesTouched: [
                        FileTouch(
                            relativePath: "Sources/MnemeCore/Activity/ActivityLogService.swift",
                            touchCount: 1,
                            lastModifiedAt: Date(timeIntervalSince1970: 1_000)
                        )
                    ],
                    commits: [
                        GitCommit(shortHash: "abc1234", message: "Implement activity summary", filesChanged: 2)
                    ]
                )
            ])
            Task.detached(priority: .utility) {
                do {
                    let summary = try await generator.summarize(activity)
                    print("activity.summary=\(summary)")
                    fflush(stdout)
                    exit(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 6 : 0)
                } catch {
                    print("activity.summary.error=\(error.localizedDescription)")
                    fflush(stdout)
                    exit(6)
                }
            }
            dispatchMain()
        }
        let environment = AppEnvironment.make()
        if ProcessInfo.processInfo.environment["MNEME_DIAGNOSTIC"] == "1" {
            print("embedder.id=\(environment.embedder.id)")
            print("embedder.dimension=\(environment.embedder.dimension)")
            let embedder = environment.embedder
            switch Self.runBlocking({ try await embedder.embed(["privacy search"], kind: .query) }) {
            case let .success(vectors):
                let vector = vectors.first ?? []
                let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
                print("embedder.sample.count=\(vector.count)")
                print("embedder.sample.norm=\(String(format: "%.4f", norm))")
            case let .failure(error):
                print("embedder.sample.error=\(error.localizedDescription)")
                fflush(stdout)
                exit(2)
            }
            switch Self.runBlocking({
                let queryVector = try await embedder.embed(["本地 隐私 搜索 文件"], kind: .query)[0]
                let passages = try await embedder.embed([
                    "Mneme provides local private search over personal files.",
                    "A banana cake recipe uses ripe fruit and flour."
                ], kind: .passage)
                return (Self.dot(queryVector, passages[0]), Self.dot(queryVector, passages[1]))
            }) {
            case let .success(scores):
                print("embedder.crossLanguage.positive=\(String(format: "%.4f", scores.0))")
                print("embedder.crossLanguage.negative=\(String(format: "%.4f", scores.1))")
                print("embedder.crossLanguage.pass=\(scores.0 > scores.1)")
                if scores.0 <= scores.1 {
                    fflush(stdout)
                    exit(3)
                }
            case let .failure(error):
                print("embedder.crossLanguage.error=\(error.localizedDescription)")
                fflush(stdout)
                exit(3)
            }
            fflush(stdout)
            exit(0)
        }
        _env = StateObject(wrappedValue: environment)
    }

    var body: some Scene {
        MenuBarExtra("Mneme", systemImage: "brain") {
            MenuBarContent()
                .environmentObject(env)
        }
        .menuBarExtraStyle(.window)

        Window("Mneme", id: "main") {
            MainWindow()
                .environmentObject(env)
        }

        Settings {
            SettingsView()
                .environmentObject(env)
        }
    }

    private static func runBlocking<T>(_ operation: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<T, Error>?

        Task.detached {
            let value: Result<T, Error>
            do {
                value = .success(try await operation())
            } catch {
                value = .failure(error)
            }
            lock.withLock {
                result = value
            }
            semaphore.signal()
        }

        semaphore.wait()
        return lock.withLock {
            result ?? .failure(EmbeddingDiagnosticError.missingResult)
        }
    }

    nonisolated private static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    }

    private static func collectTranscript(
        service: any TranscriptionService,
        audio: URL,
        options: TranscribeOptions
    ) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for try await segment in service.transcribe(audio, options: options) {
            segments.append(segment)
        }
        return segments
    }
}

private enum EmbeddingDiagnosticError: Error {
    case missingResult
}
