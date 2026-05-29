import XCTest
@testable import MnemeCore

final class ActivityLogServiceTests: XCTestCase {
    private var workspace: URL!
    private var dailyDirectory: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ActivityService-\(UUID().uuidString)", isDirectory: true)
        workspace = base.appendingPathComponent("Mneme", isDirectory: true)
        dailyDirectory = base.appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dailyDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent())
    }

    func test_refresh_collectsWorkspaceActivityAndWritesDailyNote() throws {
        let since = Date(timeIntervalSince1970: 1_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_100)
        let file = workspace.appendingPathComponent("Sources/main.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "print(\"activity\")".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)

        let service = ActivityLogService(
            workspaceRoots: [workspace],
            gitRepositories: [],
            dailyNotesDirectory: dailyDirectory
        )
        let result = try service.refresh(day: "2026-05-29", since: since)

        XCTAssertEqual(result.activity.projects.count, 1)
        XCTAssertEqual(result.activity.projects[0].name, "Mneme")
        XCTAssertEqual(result.activity.projects[0].filesTouched.map(\.relativePath), ["Sources/main.swift"])
        XCTAssertTrue(result.noteURL.path.hasSuffix("Daily/2026-05-29.md"))

        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        XCTAssertTrue(note.contains(DailyActivityRenderer.startMarker))
        XCTAssertTrue(note.contains("Sources/main.swift"))
    }
}
