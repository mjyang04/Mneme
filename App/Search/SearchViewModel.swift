import Foundation
import MnemeCore

enum SearchMode: String, CaseIterable, Identifiable {
    case search = "Search"
    case ask = "Ask"

    var id: String { rawValue }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var mode: SearchMode = .search
    @Published var queryText = ""
    @Published var hits: [SearchHit] = []
    @Published var answer: RagAnswer?
    @Published var isSearching = false

    private var query: QueryService?

    func attach(_ query: QueryService) {
        if self.query == nil {
            self.query = query
        }
    }

    func search(_ text: String) async {
        guard let query else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            answer = nil
            return
        }

        do {
            try await Task.sleep(nanoseconds: 150_000_000)
        } catch {
            return
        }

        isSearching = true
        defer { isSearching = false }
        if mode == .ask {
            answer = RagAnswer(text: "生成中...", citations: [])
            do {
                for try await partial in query.answerStream(trimmed, topK: 8) {
                    guard !Task.isCancelled else { return }
                    answer = partial
                    hits = partial.citations
                }
            } catch {
                if !Task.isCancelled {
                    answer = RagAnswer(text: "回答失败: \(error.localizedDescription)", citations: [])
                    hits = []
                }
            }
        } else {
            let results = (try? await query.search(trimmed, topK: 30)) ?? []
            if !Task.isCancelled {
                answer = nil
                hits = results
            }
        }
    }
}
