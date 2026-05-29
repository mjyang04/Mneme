import XCTest
@testable import MnemeCore

final class ActivityConnectorTests: XCTestCase {
    private var dailyDirectory: URL!

    override func setUpWithError() throws {
        dailyDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ActivityDaily-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDirectory, withIntermediateDirectories: true)
        try """
        # 2026-05-29

        \(DailyActivityRenderer.startMarker)
        ## 今日活动(自动)

        ### Mneme
        - 改动文件 1: `Sources/main.swift`
        \(DailyActivityRenderer.endMarker)
        """
        .write(to: dailyDirectory.appendingPathComponent("2026-05-29.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dailyDirectory)
    }

    func test_activityConnector_extractsDailyNotesAsActivityDocuments() throws {
        let connector = ActivityConnector(root: dailyDirectory, sourceId: "activity")
        let items = try connector.enumerate()
        let document = try connector.extract(items[0])

        XCTAssertEqual(connector.kind, .activity)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(document.title, "Activity 2026-05-29")
        XCTAssertEqual(document.meta["date"], "2026-05-29")
        XCTAssertTrue(document.text.contains("今日活动"))
        XCTAssertTrue(document.text.contains("Sources/main.swift"))
    }
}
