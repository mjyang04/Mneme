import XCTest
@testable import MnemeCore

final class TranscriptObsidianExporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TranscriptExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_exportWritesFrontmatterAndTimestampedSegments() throws {
        let exporter = TranscriptObsidianExporter(outputDirectory: directory)
        let document = sampleTranscript()

        let url = try exporter.export(document)
        let markdown = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(markdown.contains("type: transcript"))
        XCTAssertTrue(markdown.contains("language: en"))
        XCTAssertTrue(markdown.contains("- [00:00] Intro"))
        XCTAssertTrue(markdown.contains("- [00:05] Discussion"))
    }

    func test_reexportPreservesUserNotesOutsideManagedBlock() throws {
        let exporter = TranscriptObsidianExporter(outputDirectory: directory)
        let document = sampleTranscript()
        let url = try exporter.export(document)
        try "\nUser note after export.\n".write(to: url, atomically: false, encoding: .utf8)

        _ = try exporter.export(document)
        let markdown = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(markdown.contains("User note after export."))
        XCTAssertEqual(markdown.components(separatedBy: TranscriptObsidianExporter.startMarker).count, 2)
    }

    func test_exportUsesUniquePathForSameDaySameTitleTranscripts() throws {
        let exporter = TranscriptObsidianExporter(outputDirectory: directory)
        let first = sampleTranscript(id: "abc")
        let second = sampleTranscript(id: "def")

        let firstURL = try exporter.export(first)
        let secondURL = try exporter.export(second)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    private func sampleTranscript(id: String = "abc") -> TranscriptDocument {
        TranscriptDocument(
            id: id,
            title: "Research Meeting",
            sourceAudioPath: "voice.m4a",
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
