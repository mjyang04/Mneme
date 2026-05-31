import XCTest
@testable import MnemeCore

final class FtsQueryBuilderTests: XCTestCase {
    func test_buildTokenizesEnglishAndEscapesQuotes() {
        XCTAssertEqual(
            FtsQueryBuilder.build(#"CoreML "e5" search"#),
            #""coreml" OR "e5" OR "search""#
        )
    }

    func test_buildAddsCJKBigrams() {
        XCTAssertEqual(
            FtsQueryBuilder.build("研究方法"),
            #""研究" OR "究方" OR "方法""#
        )
    }

    func test_buildReturnsEmptyForPunctuationOnlyQuery() {
        XCTAssertEqual(FtsQueryBuilder.build("!!! ..."), "")
    }

    func test_buildAddsJapaneseAndHangulBigrams() {
        XCTAssertEqual(
            FtsQueryBuilder.build("研究メモ"),
            #""研究" OR "究メ" OR "メモ""#
        )
        XCTAssertEqual(
            FtsQueryBuilder.build("로컬검색"),
            #""로컬" OR "컬검" OR "검색""#
        )
    }

    func test_indexTextAppendsCJKBigrams() {
        let indexed = FtsQueryBuilder.indexText("本地研究方法")
        XCTAssertTrue(indexed.contains("本地"))
        XCTAssertTrue(indexed.contains("地研"))
        XCTAssertTrue(indexed.contains("研究"))
        XCTAssertTrue(indexed.contains("方法"))
    }

    func test_indexTextAppendsJapaneseAndHangulBigrams() {
        let indexed = FtsQueryBuilder.indexText("研究メモ 로컬검색")
        XCTAssertTrue(indexed.contains("究メ"))
        XCTAssertTrue(indexed.contains("メモ"))
        XCTAssertTrue(indexed.contains("로컬"))
        XCTAssertTrue(indexed.contains("검색"))
    }
}
