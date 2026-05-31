import XCTest
@testable import MnemeCore

final class PDFConnectorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("papers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try PDFTestSupport.makeTextPDF(
            "retrieval augmented generation for research",
            at: dir.appendingPathComponent("paper.pdf")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func test_enumerate_findsPDFs() throws {
        XCTAssertEqual(try PDFConnector(root: dir, sourceId: "p1").enumerate().count, 1)
    }

    func test_extract_pullsText() throws {
        let connector = PDFConnector(root: dir, sourceId: "p1")
        let document = try connector.extract(connector.enumerate()[0])
        XCTAssertTrue(document.text.contains("retrieval augmented generation"))
        XCTAssertEqual(document.title, "paper")
    }
}
