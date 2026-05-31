import Foundation

public struct MemoryWrite: Equatable, Sendable {
    public let key: String
    public let url: URL
    public let deduped: Bool
}

public struct MemoryStore: Sendable {
    public static let defaultSourceId = "mneme-memory"
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func write(_ input: RememberInputDTO, now: Date = Date()) throws -> MemoryWrite {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw MnemeAgentError.invalidArgument("remember requires non-empty text")
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = Self.stableKey(text: text, sourceRef: input.sourceRef)
        let url = directory.appendingPathComponent("mem-\(key).md")
        if FileManager.default.fileExists(atPath: url.path) {
            return MemoryWrite(key: key, url: url, deduped: true)
        }

        let markdown = renderMarkdown(
            key: key,
            input: RememberInputDTO(
                text: text,
                tags: input.tags,
                sourceRef: input.sourceRef,
                link: input.link,
                title: input.title
            ),
            createdAt: now
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return MemoryWrite(key: key, url: url, deduped: false)
    }

    public static func stableKey(text: String, sourceRef: String?) -> String {
        ContentHash.of("\(normalize(text))|\(sourceRef ?? "")")
    }

    private static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderMarkdown(key: String, input: RememberInputDTO, createdAt: Date) -> String {
        var lines: [String] = [
            "---",
            "type: mneme-memory",
            "key: \(key)",
            "created: \(ISO8601DateFormatter().string(from: createdAt))"
        ]
        if let title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("title: \(Self.yamlScalar(title))")
        }
        if let tags = input.tags?.map(Self.normalizeTag).filter({ !$0.isEmpty }), !tags.isEmpty {
            lines.append("tags:")
            for tag in tags {
                lines.append("  - \(Self.yamlScalar(tag))")
            }
        }
        if let sourceRef = input.sourceRef?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceRef.isEmpty {
            lines.append("source_ref: \(Self.yamlScalar(sourceRef))")
        }
        if let link = input.link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty {
            lines.append("link: \(Self.yamlScalar(link))")
        }
        lines.append("---")
        lines.append("")
        lines.append(input.text.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func normalizeTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func yamlScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
