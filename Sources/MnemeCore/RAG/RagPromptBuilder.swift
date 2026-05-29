import Foundation

public enum RagPromptBuilder {
    public static func prompt(question: String, citations: [SearchHit]) -> String {
        let evidence = citations.enumerated().map { index, hit in
            let title = hit.title ?? hit.uri.lastPathComponent
            let text = normalize(hit.text)
            let line: String = "[\(index + 1)] \(title)\n\(text)"
            return line
        }.joined(separator: "\n\n")

        return """
        你是本地研究助手。仅依据【资料】回答；资料不足就说不知道。
        用与问题相同的语言简洁回答，并在引用处标注 [n]。不要编造未出现在资料中的事实。
        不要输出推理过程、chain-of-thought 或 <think> 标签，只输出最终答案。

        【资料】
        \(evidence)

        【问题】
        \(question)
        """
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
