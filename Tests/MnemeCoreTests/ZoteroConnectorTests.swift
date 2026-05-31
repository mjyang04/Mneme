import GRDB
import XCTest
@testable import MnemeCore

final class ZoteroConnectorTests: XCTestCase {
    private var library: URL!
    private var cache: URL!

    override func setUpWithError() throws {
        library = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zotero-\(UUID().uuidString)", isDirectory: true)
        cache = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zotero-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try makeZoteroSQLite(at: library.appendingPathComponent("zotero.sqlite").path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: library)
        try? FileManager.default.removeItem(at: cache)
    }

    func test_enumerateAndExtractZoteroMetadata() throws {
        let connector = ZoteroConnector(libraryRoot: library, sourceId: "zotero", cacheDir: cache)
        let items = try connector.enumerate()
        XCTAssertEqual(items.map(\.id), ["zotero://item/ABC123"])

        let document = try connector.extract(try XCTUnwrap(items.first))
        XCTAssertEqual(document.title, "Local-first Research Memory")
        XCTAssertEqual(document.meta["zotero_key"], "ABC123")
        XCTAssertEqual(document.meta["item_type"], "journalArticle")
        XCTAssertEqual(document.meta["year"], "2026")
        XCTAssertEqual(document.meta["tags"], "mneme, agent")
        XCTAssertEqual(document.meta["authors"], "Mingjia Yang")
        XCTAssertTrue(document.text.contains("Local-first Research Memory"))
        XCTAssertTrue(document.text.contains("Agent memory layer abstract"))
    }

    func test_extractUsesCachedItemsAfterEnumeration() throws {
        let connector = ZoteroConnector(libraryRoot: library, sourceId: "zotero", cacheDir: cache)
        let item = try XCTUnwrap(connector.enumerate().first)

        try FileManager.default.removeItem(at: library.appendingPathComponent("zotero.sqlite"))

        let document = try connector.extract(item)
        XCTAssertEqual(document.title, "Local-first Research Memory")
        XCTAssertEqual(document.meta["zotero_key"], "ABC123")
    }

    private func makeZoteroSQLite(at path: String) throws {
        let dbQueue = try DatabaseQueue(path: path)
        try dbQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE itemTypes (itemTypeID INTEGER PRIMARY KEY, typeName TEXT);
            CREATE TABLE items (itemID INTEGER PRIMARY KEY, key TEXT, itemTypeID INTEGER);
            CREATE TABLE fields (fieldID INTEGER PRIMARY KEY, fieldName TEXT);
            CREATE TABLE itemDataValues (valueID INTEGER PRIMARY KEY, value TEXT);
            CREATE TABLE itemData (itemID INTEGER, fieldID INTEGER, valueID INTEGER);
            CREATE TABLE deletedItems (itemID INTEGER);
            CREATE TABLE tags (tagID INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE itemTags (itemID INTEGER, tagID INTEGER);
            CREATE TABLE creators (creatorID INTEGER PRIMARY KEY, firstName TEXT, lastName TEXT);
            CREATE TABLE itemCreators (itemID INTEGER, creatorID INTEGER, orderIndex INTEGER);
            INSERT INTO itemTypes VALUES (1, 'journalArticle');
            INSERT INTO items VALUES (10, 'ABC123', 1);
            INSERT INTO fields VALUES (1, 'title'), (2, 'abstractNote'), (3, 'date');
            INSERT INTO itemDataValues VALUES
                (1, 'Local-first Research Memory'),
                (2, 'Agent memory layer abstract'),
                (3, '2026-05-29');
            INSERT INTO itemData VALUES (10, 1, 1), (10, 2, 2), (10, 3, 3);
            INSERT INTO tags VALUES (1, 'mneme'), (2, 'agent');
            INSERT INTO itemTags VALUES (10, 1), (10, 2);
            INSERT INTO creators VALUES (1, 'Mingjia', 'Yang');
            INSERT INTO itemCreators VALUES (10, 1, 0);
            """)
        }
    }
}
