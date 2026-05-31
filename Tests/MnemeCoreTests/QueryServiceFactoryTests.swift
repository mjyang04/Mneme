import XCTest
@testable import MnemeCore

final class QueryServiceFactoryTests: XCTestCase {
    func test_makeReadWriteCreatesExplicitAppSupportDirectory() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mneme-factory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtime = try QueryServiceFactory.makeReadWrite(appSupportDirectory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.databaseURL.path))
    }
}
