import Foundation

public enum RankFusion {
    public static func rrf(_ rankedLists: [[SearchHit]], k: Float = 60) -> [SearchHit] {
        var bestHitByChunk: [String: SearchHit] = [:]
        var scoreByChunk: [String: Float] = [:]

        for hits in rankedLists {
            for (offset, hit) in hits.enumerated() {
                let rank = Float(offset + 1)
                scoreByChunk[hit.chunkId, default: 0] += 1 / (k + rank)
                if bestHitByChunk[hit.chunkId] == nil {
                    bestHitByChunk[hit.chunkId] = hit
                }
            }
        }

        return scoreByChunk.compactMap { chunkId, score in
            guard let hit = bestHitByChunk[chunkId] else {
                return nil
            }
            return SearchHit(
                chunkId: hit.chunkId,
                documentId: hit.documentId,
                score: score,
                text: hit.text,
                title: hit.title,
                uri: hit.uri,
                kind: hit.kind,
                locator: hit.locator,
                meta: hit.meta
            )
        }
        .sorted { $0.score > $1.score }
    }
}
