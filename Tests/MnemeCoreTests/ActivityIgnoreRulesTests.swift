import XCTest
@testable import MnemeCore

final class ActivityIgnoreRulesTests: XCTestCase {
    func test_defaultRules_ignoreNoisyPaths() {
        let rules = ActivityIgnoreRules.default

        XCTAssertTrue(rules.shouldIgnore(relativePath: ".git/config"))
        XCTAssertTrue(rules.shouldIgnore(relativePath: "node_modules/lib/index.js"))
        XCTAssertTrue(rules.shouldIgnore(relativePath: "build/output.o"))
        XCTAssertTrue(rules.shouldIgnore(relativePath: "outputs/report.json"))
        XCTAssertTrue(rules.shouldIgnore(relativePath: "Package.lock"))
        XCTAssertTrue(rules.shouldIgnore(relativePath: ".DS_Store"))
        XCTAssertTrue(rules.shouldIgnore(relativePath: "notes/.draft.swp"))
    }

    func test_defaultRules_allowUsefulSourceFiles() {
        let rules = ActivityIgnoreRules.default

        XCTAssertFalse(rules.shouldIgnore(relativePath: "Sources/MnemeCore/Activity/Foo.swift"))
        XCTAssertFalse(rules.shouldIgnore(relativePath: "docs/03-module-activity-log.md"))
    }
}
