import AppKit
import MnemeCore
import SwiftUI

struct QuickSearchView: View {
    let query: QueryService
    let onClose: () -> Void

    @State private var text = ""
    @State private var hits: [SearchHit] = []
    @State private var answer: RagAnswer?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            TextField("问我的文件...", text: $text)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(14)
                .onChange(of: text) { _, newValue in
                    schedule(newValue)
                }

            Divider()

            if let answer {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        Text(answer.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                    Divider()
                    List(Array(answer.citations.enumerated()), id: \.element.chunkId) { index, hit in
                        HStack(alignment: .top, spacing: 8) {
                            Text("[\(index + 1)]")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                            ResultRow(hit: hit)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    ResultOpener.open(hit)
                                    onClose()
                                }
                        }
                    }
                    .frame(height: 170)
                }
            } else if hits.isEmpty {
                ContentUnavailableView("无结果", systemImage: "magnifyingglass")
                    .frame(maxHeight: .infinity)
            } else {
                List(hits, id: \.chunkId) { hit in
                    ResultRow(hit: hit)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            ResultOpener.open(hit)
                            onClose()
                        }
                }
            }
        }
        .frame(width: 680, height: 430)
        .onExitCommand {
            onClose()
        }
    }

    private func schedule(_ queryText: String) {
        task?.cancel()
        task = Task {
            let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await MainActor.run {
                    hits = []
                    answer = nil
                }
                return
            }
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if trimmed.hasPrefix("?") {
                let question = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    answer = RagAnswer(text: "生成中...", citations: [])
                    hits = []
                }
                do {
                    for try await partial in query.answerStream(question, topK: 8) {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            answer = partial
                            hits = partial.citations
                        }
                    }
                } catch {
                    await MainActor.run {
                        answer = RagAnswer(text: "回答失败: \(error.localizedDescription)", citations: [])
                        hits = []
                    }
                }
                return
            }

            let results = (try? await query.search(trimmed, topK: 20)) ?? []
            await MainActor.run {
                answer = nil
                hits = results
            }
        }
    }
}
