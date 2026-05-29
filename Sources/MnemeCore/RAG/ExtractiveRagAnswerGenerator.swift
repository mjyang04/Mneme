import Foundation

public struct ExtractiveRagAnswerGenerator: RagAnswerGenerator {
    public let maxSnippetCharacters: Int

    public init(maxSnippetCharacters: Int = 360) {
        self.maxSnippetCharacters = maxSnippetCharacters
    }

    public func answer(question: String, citations: [SearchHit]) async throws -> String {
        guard !citations.isEmpty else {
            return "不知道：当前索引没有找到可引用的资料。"
        }

        var lines: [String] = ["根据已索引资料，可以先确认这些片段："]
        for (index, hit) in citations.enumerated() {
            let title = hit.title ?? hit.uri.lastPathComponent
            let snippet = trimmedSnippet(hit.text)
            lines.append("- \(title)：\(snippet) [\(index + 1)]")
        }
        lines.append("")
        lines.append("这是基于检索片段的离线摘录式回答；接入本地 LLM 后可生成更完整的综合答案。")
        return lines.joined(separator: "\n")
    }

    private func trimmedSnippet(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxSnippetCharacters else {
            return normalized
        }
        return String(normalized.prefix(maxSnippetCharacters)) + "..."
    }
}
