import Foundation

public struct MemoryConnector: SourceConnector {
    public let root: URL
    public let sourceId: String
    public let kind: SourceKind = .memory

    public init(root: URL, sourceId: String = MemoryStore.defaultSourceId) {
        self.root = root
        self.sourceId = sourceId
    }

    public func enumerate() throws -> [SourceItem] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                return SourceItem(
                    id: Self.documentId(for: url),
                    uri: url,
                    modifiedAt: values.contentModificationDate
                )
            }
            .sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let content = try String(contentsOf: item.uri, encoding: .utf8)
        let parsed = Self.parse(content)
        return ExtractedDocument(
            id: item.id,
            title: parsed.title ?? item.uri.deletingPathExtension().lastPathComponent,
            text: parsed.body,
            contentHash: ContentHash.of(content),
            meta: parsed.meta
        )
    }

    public static func documentId(for url: URL) -> String {
        "memory://\(url.deletingPathExtension().lastPathComponent)"
    }

    static func parse(_ content: String) -> (title: String?, body: String, meta: [String: String]) {
        guard content.hasPrefix("---\n"),
              let endRange = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) else {
            return (nil, content.trimmingCharacters(in: .whitespacesAndNewlines), [:])
        }

        let frontmatter = String(content[content.index(content.startIndex, offsetBy: 4)..<endRange.lowerBound])
        let body = String(content[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var meta: [String: String] = [:]
        var listValues: [String: [String]] = [:]
        var currentListKey: String?
        var title: String?
        for line in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            if let key = currentListKey,
               rawLine.hasPrefix("  - ") || rawLine.hasPrefix("- ") {
                let rawValue = rawLine
                    .replacingOccurrences(of: #"^\s*-\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let value = unquote(rawValue)
                if !value.isEmpty {
                    listValues[key, default: []].append(value)
                }
                continue
            }

            currentListKey = nil
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            if value.isEmpty {
                currentListKey = key
                continue
            }
            if key == "title" {
                title = value
            }
            if !value.isEmpty {
                meta[key] = value
            }
        }
        for (key, values) in listValues where !values.isEmpty {
            meta[key] = values.joined(separator: ", ")
        }
        return (title, body, meta)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              value.first == "\"",
              value.last == "\"" else {
            return value
        }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
