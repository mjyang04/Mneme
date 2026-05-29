import XCTest
@testable import MnemeCore

final class CodeConnectorTests: XCTestCase {
    private var repo: URL!

    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("node_modules"),
            withIntermediateDirectories: true
        )
        try "func main() { print(\"hi\") }"
            .write(to: repo.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "module.exports = {}"
            .write(
                to: repo.appendingPathComponent("node_modules/lib.js"),
                atomically: true,
                encoding: .utf8
            )
        try "binary-ish"
            .write(to: repo.appendingPathComponent("data.bin"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    func test_enumerate_skipsIgnoredDirsAndNonCode() throws {
        let items = try CodeConnector(root: repo, sourceId: "c1").enumerate()
        XCTAssertEqual(items.map { $0.uri.lastPathComponent }, ["main.swift"])
    }

    func test_extract_setsLanguageMeta() throws {
        let connector = CodeConnector(root: repo, sourceId: "c1")
        let document = try connector.extract(connector.enumerate()[0])
        XCTAssertEqual(document.meta["language"], "swift")
        XCTAssertTrue(document.text.contains("func main"))
        XCTAssertEqual(document.title, "main.swift")
    }
}
