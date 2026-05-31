import XCTest
@testable import MnemeCore

final class ActivityEventBatcherTests: XCTestCase {
    func test_record_keepsOnlyEventsInsideWorkspaceAndAppliesIgnoreRules() {
        let root = URL(fileURLWithPath: "/tmp/Mneme", isDirectory: true)
        let batcher = ActivityEventBatcher(workspaceRoots: [root], ignoreRules: .default)

        XCTAssertTrue(batcher.record(URL(fileURLWithPath: "/tmp/Mneme/Sources/main.swift")))
        XCTAssertFalse(batcher.record(URL(fileURLWithPath: "/tmp/Mneme/node_modules/lib.js")))
        XCTAssertFalse(batcher.record(URL(fileURLWithPath: "/tmp/Other/file.swift")))

        let batch = batcher.drain()

        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch[0].workspaceRoot, root.standardizedFileURL)
        XCTAssertEqual(batch[0].relativePath, "Sources/main.swift")
    }

    func test_record_deduplicatesRepeatedEvents() {
        let root = URL(fileURLWithPath: "/tmp/Mneme", isDirectory: true)
        let batcher = ActivityEventBatcher(workspaceRoots: [root], ignoreRules: .default)
        let url = URL(fileURLWithPath: "/tmp/Mneme/Sources/main.swift")

        XCTAssertTrue(batcher.record(url))
        XCTAssertTrue(batcher.record(url))

        XCTAssertEqual(batcher.drain().count, 1)
        XCTAssertTrue(batcher.drain().isEmpty)
    }

    func test_record_doesNotTreatSiblingPrefixAsInsideWorkspace() {
        let root = URL(fileURLWithPath: "/tmp/Mneme", isDirectory: true)
        let batcher = ActivityEventBatcher(workspaceRoots: [root], ignoreRules: .default)

        XCTAssertFalse(batcher.record(URL(fileURLWithPath: "/tmp/Mneme2/Sources/main.swift")))

        XCTAssertTrue(batcher.drain().isEmpty)
    }
}
