import XCTest
@testable import MnemeCore

final class TranscriptStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TranscriptStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_saveAndLoadTranscriptRoundTripsSegments() throws {
        let store = TranscriptStore(directory: directory)
        let document = sampleTranscript()

        try store.save(document)
        let loaded = try store.load(id: document.id)

        XCTAssertEqual(loaded, document)
        XCTAssertEqual(try store.list().map(\.id), [document.id])
    }

    func test_importPlainTextCreatesSingleSegmentTranscript() throws {
        let store = TranscriptStore(directory: directory)
        let service = TranscriptImportService(store: store)

        let document = try service.importPlainText(
            title: "Meeting",
            text: "We discussed local search.",
            language: "en"
        )

        XCTAssertEqual(document.title, "Meeting")
        XCTAssertEqual(document.language, "en")
        XCTAssertEqual(document.segments.map(\.text), ["We discussed local search."])
        XCTAssertEqual(try store.list().count, 1)
    }

    func test_importAudioCollectsSegmentsAndStoresSourceAudioMetadata() async throws {
        let store = TranscriptStore(directory: directory)
        let service = TranscriptImportService(
            store: store,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let audio = directory.appendingPathComponent("meeting.m4a")
        try Data().write(to: audio)

        let document = try await service.importAudio(
            audio: audio,
            options: TranscribeOptions(model: "tiny", language: "en"),
            service: StubTranscriptionService(segments: [
                TranscriptSegment(start: 0, end: 2.5, text: " Hello "),
                TranscriptSegment(start: 2.5, end: 6, text: "local transcript")
            ])
        )

        XCTAssertEqual(document.id, "meeting-2000")
        XCTAssertEqual(document.title, "meeting")
        XCTAssertEqual(document.sourceAudioPath, audio.path)
        XCTAssertEqual(document.duration, 6)
        XCTAssertEqual(document.language, "en")
        XCTAssertEqual(document.model, "tiny")
        XCTAssertEqual(document.segments.map(\.text), ["Hello", "local transcript"])
        XCTAssertEqual(try store.list(), [document])
    }

    func test_importAudioRejectsUnsupportedAudioExtension() async throws {
        let store = TranscriptStore(directory: directory)
        let service = TranscriptImportService(store: store)
        let url = directory.appendingPathComponent("notes.txt")

        do {
            _ = try await service.importAudio(
                audio: url,
                service: StubTranscriptionService(segments: [])
            )
            XCTFail("Expected unsupported extension error")
        } catch let error as TranscriptImportError {
            XCTAssertEqual(error, .unsupportedAudioExtension("txt"))
        }
    }

    func test_textCleanerRemovesWhisperSpecialTokens() {
        let raw = "<|startoftranscript|><|en|><|transcribe|><|0.00|> Hello<|2.00|><|endoftext|>"

        XCTAssertEqual(TranscriptTextCleaner.clean(raw), "Hello")
    }

    private func sampleTranscript() -> TranscriptDocument {
        TranscriptDocument(
            id: "abc",
            title: "Research Meeting",
            sourceAudioPath: "/tmp/audio.m4a",
            duration: 12.5,
            language: "en",
            model: "manual",
            createdAt: Date(timeIntervalSince1970: 1_000),
            segments: [
                TranscriptSegment(start: 0, end: 5, text: "Intro"),
                TranscriptSegment(start: 5, end: 12.5, text: "Discussion")
            ]
        )
    }
}

private struct StubTranscriptionService: TranscriptionService {
    let segments: [TranscriptSegment]

    func transcribe(_ audio: URL, options: TranscribeOptions) -> AsyncThrowingStream<TranscriptSegment, Error> {
        AsyncThrowingStream { continuation in
            for segment in segments {
                continuation.yield(segment)
            }
            continuation.finish()
        }
    }
}
