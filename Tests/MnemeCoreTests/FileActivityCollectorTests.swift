import XCTest
@testable import MnemeCore

final class FileActivityCollectorTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ActivityWorkspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func test_collectTouchedFiles_filtersByDateAndIgnoreRules() throws {
        let since = Date(timeIntervalSince1970: 1_000)
        let oldDate = Date(timeIntervalSince1970: 900)
        let newDate = Date(timeIntervalSince1970: 1_100)

        try write("print(\"hi\")", to: "Sources/main.swift", modifiedAt: newDate)
        try write("old", to: "docs/old.md", modifiedAt: oldDate)
        try write("ignored", to: "node_modules/lib.js", modifiedAt: newDate)

        let collector = FileActivityCollector(ignoreRules: .default)
        let touches = try collector.collect(root: workspace, since: since)

        XCTAssertEqual(touches.map(\.relativePath), ["Sources/main.swift"])
        XCTAssertEqual(touches[0].touchCount, 1)
        XCTAssertEqual(touches[0].lastModifiedAt, newDate)
    }

    private func write(_ text: String, to relativePath: String, modifiedAt: Date) throws {
        let url = workspace.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: url.path
        )
    }
}
