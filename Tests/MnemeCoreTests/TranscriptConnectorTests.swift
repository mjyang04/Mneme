import XCTest
@testable import MnemeCore

final class TranscriptConnectorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TranscriptConnector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_connectorIndexesStoredTranscriptsAsTranscriptDocuments() throws {
        let store = TranscriptStore(directory: directory)
        let document = TranscriptDocument(
            id: "meeting",
            title: "Meeting",
            sourceAudioPath: nil,
            duration: 10,
            language: "en",
            model: "manual",
            createdAt: Date(timeIntervalSince1970: 1_000),
            segments: [
                TranscriptSegment(start: 0, end: 4, text: "Mneme can search transcripts."),
                TranscriptSegment(start: 4, end: 10, text: "Everything stays local.")
            ]
        )
        try store.save(document)

        let connector = TranscriptConnector(root: directory, sourceId: "transcripts")
        let item = try XCTUnwrap(connector.enumerate().first)
        let extracted = try connector.extract(item)

        XCTAssertEqual(connector.kind, .transcript)
        XCTAssertEqual(extracted.title, "Meeting")
        XCTAssertEqual(extracted.meta["language"], "en")
        XCTAssertTrue(extracted.text.contains("Mneme can search transcripts."))
        XCTAssertTrue(extracted.text.contains("Everything stays local."))
    }
}
