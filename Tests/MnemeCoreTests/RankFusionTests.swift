import XCTest
@testable import MnemeCore

final class RankFusionTests: XCTestCase {
    func test_rrfCombinesRankedListsByChunk() {
        func hit(_ id: String, score: Float) -> SearchHit {
            SearchHit(
                chunkId: id,
                documentId: id,
                score: score,
                text: id,
                title: id,
                uri: URL(fileURLWithPath: "/tmp/\(id).md"),
                kind: .notes,
                locator: nil
            )
        }

        let fused = RankFusion.rrf([
            [hit("A", score: 0.9), hit("B", score: 0.8)],
            [hit("B", score: 10), hit("C", score: 9)]
        ])
        XCTAssertEqual(fused.map(\.chunkId), ["B", "A", "C"])
        XCTAssertGreaterThan(fused[0].score, fused[1].score)
    }
}
