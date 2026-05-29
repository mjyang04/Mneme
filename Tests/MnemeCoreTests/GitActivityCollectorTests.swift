import XCTest
@testable import MnemeCore

final class GitActivityCollectorTests: XCTestCase {
    func test_parseLog_collectsCommitsAndChangedFileCounts() {
        let output = """
        commit abcdef1234567890
        Implement activity log
        2\t1\tSources/MnemeCore/Activity/ActivityLogService.swift
        5\t0\tTests/MnemeCoreTests/ActivityLogServiceTests.swift

        commit 1234567890abcdef
        Update docs
        1\t1\tdocs/03-module-activity-log.md

        """

        let commits = GitActivityCollector.parseLog(output)

        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].shortHash, "abcdef1")
        XCTAssertEqual(commits[0].message, "Implement activity log")
        XCTAssertEqual(commits[0].filesChanged, 2)
        XCTAssertEqual(commits[1].shortHash, "1234567")
        XCTAssertEqual(commits[1].message, "Update docs")
        XCTAssertEqual(commits[1].filesChanged, 1)
    }
}
