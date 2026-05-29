import XCTest
@testable import MnemeCore

final class NotesConnectorTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )
        try "---\ntitle: My Note\ntags: ai\n---\n# Heading\nsome content here [[Other]]"
            .write(to: vault.appendingPathComponent("note1.md"), atomically: true, encoding: .utf8)
        try "just plain text, no frontmatter"
            .write(to: vault.appendingPathComponent("note2.md"), atomically: true, encoding: .utf8)
        try "should be ignored"
            .write(
                to: vault.appendingPathComponent(".obsidian/app.md"),
                atomically: true,
                encoding: .utf8
            )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func test_enumerate_skipsObsidianDir() throws {
        let connector = NotesConnector(root: vault, sourceId: "s1")
        XCTAssertEqual(try connector.enumerate().count, 2)
    }

    func test_extract_parsesFrontmatterAndTitle() throws {
        let connector = NotesConnector(root: vault, sourceId: "s1")
        let item = try XCTUnwrap(connector.enumerate().first { $0.uri.lastPathComponent == "note1.md" })
        let document = try connector.extract(item)

        XCTAssertEqual(document.title, "My Note")
        XCTAssertEqual(document.meta["tags"], "ai")
        XCTAssertEqual(document.meta["wikilinks"], "Other")
        XCTAssertTrue(document.text.contains("some content here"))
        XCTAssertFalse(document.text.contains("---"))
    }

    func test_extract_fallsBackToFilenameTitle() throws {
        let connector = NotesConnector(root: vault, sourceId: "s1")
        let item = try XCTUnwrap(connector.enumerate().first { $0.uri.lastPathComponent == "note2.md" })
        XCTAssertEqual(try connector.extract(item).title, "note2")
    }
}
