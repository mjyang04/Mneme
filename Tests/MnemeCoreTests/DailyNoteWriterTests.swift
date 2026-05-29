import XCTest
@testable import MnemeCore

final class DailyNoteWriterTests: XCTestCase {
    private var dailyDirectory: URL!

    override func setUpWithError() throws {
        dailyDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Daily-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dailyDirectory)
    }

    func test_render_includesManagedMarkersAndActivity() {
        let activity = sampleActivity()
        let markdown = DailyActivityRenderer().render(activity)

        XCTAssertTrue(markdown.contains(DailyActivityRenderer.startMarker))
        XCTAssertTrue(markdown.contains("## 今日活动(自动)"))
        XCTAssertTrue(markdown.contains("### Mneme"))
        XCTAssertTrue(markdown.contains("提交 1 笔"))
        XCTAssertTrue(markdown.contains("Sources/main.swift"))
        XCTAssertTrue(markdown.contains(DailyActivityRenderer.endMarker))
    }

    func test_render_placesSummaryBeforeRawActivity() {
        let activity = DailyActivity(
            day: "2026-05-29",
            projects: sampleActivity().projects,
            summary: "今天主要推进 Mneme 的活动日志。"
        )
        let markdown = DailyActivityRenderer().render(activity)

        XCTAssertTrue(markdown.contains("### 摘要\n今天主要推进 Mneme 的活动日志。"))
        XCTAssertLessThan(
            markdown.range(of: "### 摘要")!.lowerBound,
            markdown.range(of: "### Mneme")!.lowerBound
        )
    }

    func test_activitySummaryPromptBuilder_includesFactsAndNoFabricationInstruction() {
        let prompt = ActivitySummaryPromptBuilder().prompt(for: sampleActivity())

        XCTAssertTrue(prompt.contains("不要杜撰"))
        XCTAssertTrue(prompt.contains("项目: Mneme"))
        XCTAssertTrue(prompt.contains("commit abcdef1"))
        XCTAssertTrue(prompt.contains("Sources/main.swift"))
    }

    func test_extractiveActivitySummary_summarizesCounts() async throws {
        let summary = try await ExtractiveActivitySummaryGenerator().summarize(sampleActivity())

        XCTAssertTrue(summary.contains("Mneme"))
        XCTAssertTrue(summary.contains("1 笔 git 提交"))
        XCTAssertTrue(summary.contains("1 个文件改动"))
    }

    func test_writer_insertsAndUpdatesManagedBlockWithoutTouchingUserText() throws {
        let writer = DailyNoteWriter(dailyDirectory: dailyDirectory)
        let path = dailyDirectory.appendingPathComponent("2026-05-29.md")
        try "# 2026-05-29\n\n用户手写内容\n".write(to: path, atomically: true, encoding: .utf8)

        try writer.writeManagedBlock("first block", day: "2026-05-29")
        var current = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(current.contains("用户手写内容"))
        XCTAssertTrue(current.contains("first block"))

        try writer.writeManagedBlock("second block", day: "2026-05-29")
        current = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(current.contains("用户手写内容"))
        XCTAssertFalse(current.contains("first block"))
        XCTAssertTrue(current.contains("second block"))
    }

    private func sampleActivity() -> DailyActivity {
        DailyActivity(day: "2026-05-29", projects: [
            ProjectActivity(
                name: "Mneme",
                rootPath: "/tmp/Mneme",
                filesTouched: [
                    FileTouch(relativePath: "Sources/main.swift", touchCount: 1, lastModifiedAt: Date(timeIntervalSince1970: 1_000))
                ],
                commits: [
                    GitCommit(shortHash: "abcdef1", message: "Implement activity log", filesChanged: 2)
                ]
            )
        ])
    }
}
