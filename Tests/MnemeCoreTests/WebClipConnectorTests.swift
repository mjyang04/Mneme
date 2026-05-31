import XCTest
@testable import MnemeCore

final class WebClipConnectorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("webclips-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_extractHTMLRemovesScriptsAndKeepsCanonicalURL() throws {
        let html = root.appendingPathComponent("clip.html")
        try """
        <html>
          <head>
            <title>Research Clip</title>
            <meta property="og:url" content="https://example.com/research">
            <script>secret()</script>
          </head>
          <body><article><h1>Finding</h1><p>Mneme &amp; local memory.</p></article></body>
        </html>
        """.write(to: html, atomically: true, encoding: .utf8)

        let connector = WebClipConnector(root: root, sourceId: "web")
        let item = try XCTUnwrap(connector.enumerate().first)
        let document = try connector.extract(item)

        XCTAssertEqual(document.title, "Research Clip")
        XCTAssertEqual(document.meta["source_url"], "https://example.com/research")
        XCTAssertTrue(document.text.contains("Finding"))
        XCTAssertTrue(document.text.contains("Mneme & local memory."))
        XCTAssertFalse(document.text.contains("secret()"))
    }

    func test_extractHTMLFindsCanonicalURLWithAttributesInAnyOrder() throws {
        let html = root.appendingPathComponent("canonical.html")
        try """
        <html>
          <head>
            <link href="https://example.com/canonical" rel="canonical">
          </head>
          <body>Canonical body.</body>
        </html>
        """.write(to: html, atomically: true, encoding: .utf8)

        let connector = WebClipConnector(root: root, sourceId: "web")
        let item = try XCTUnwrap(connector.enumerate().first { $0.uri.lastPathComponent == "canonical.html" })
        let document = try connector.extract(item)

        XCTAssertEqual(document.meta["source_url"], "https://example.com/canonical")
    }

    func test_extractMarkdownAsPlainTextWithoutHTMLTagStripping() throws {
        let markdown = root.appendingPathComponent("clip.md")
        try """
        # Research Note

        Keep comparison a < b and c > d.
        """.write(to: markdown, atomically: true, encoding: .utf8)

        let connector = WebClipConnector(root: root, sourceId: "web")
        let item = try XCTUnwrap(connector.enumerate().first { $0.uri.lastPathComponent == "clip.md" })
        let document = try connector.extract(item)

        XCTAssertEqual(document.title, "Research Note")
        XCTAssertTrue(document.text.contains("a < b"))
        XCTAssertTrue(document.text.contains("c > d"))
    }

    func test_enumerateSkipsWebArchiveFiles() throws {
        let webarchive = root.appendingPathComponent("clip.webarchive")
        try Data([0, 1, 2, 3]).write(to: webarchive)

        let connector = WebClipConnector(root: root, sourceId: "web")
        XCTAssertFalse(try connector.enumerate().contains { $0.uri.lastPathComponent == "clip.webarchive" })
    }
}
