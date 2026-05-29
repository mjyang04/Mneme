import Foundation

public enum RetrievalEval {
    public struct Aggregate: Equatable, Sendable {
        public let hitAtK: Double
        public let mrr: Double

        public init(hitAtK: Double, mrr: Double) {
            self.hitAtK = hitAtK
            self.mrr = mrr
        }
    }

    public static func hitAtK(ranked: [String], relevant: Set<String>, k: Int) -> Bool {
        ranked.prefix(k).contains { relevant.contains($0) }
    }

    public static func reciprocalRank(ranked: [String], relevant: Set<String>) -> Double {
        for (index, id) in ranked.enumerated() where relevant.contains(id) {
            return 1.0 / Double(index + 1)
        }
        return 0
    }

    public static func aggregate(
        _ rankings: [(ranked: [String], relevant: Set<String>)],
        k: Int
    ) -> Aggregate {
        guard !rankings.isEmpty else {
            return Aggregate(hitAtK: 0, mrr: 0)
        }

        let hits = rankings.map { hitAtK(ranked: $0.ranked, relevant: $0.relevant, k: k) ? 1.0 : 0.0 }
        let reciprocalRanks = rankings.map {
            reciprocalRank(ranked: $0.ranked, relevant: $0.relevant)
        }

        return Aggregate(
            hitAtK: hits.reduce(0, +) / Double(hits.count),
            mrr: reciprocalRanks.reduce(0, +) / Double(reciprocalRanks.count)
        )
    }
}
