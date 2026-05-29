import Foundation

public struct NotesConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .notes
    private let root: URL

    public init(root: URL, sourceId: String) {
        self.root = root
        self.sourceId = sourceId
    }

    public func enumerate() throws -> [SourceItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [SourceItem] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            guard !url.path.contains("/.obsidian/"), !url.path.contains("/.trash/") else {
                continue
            }
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: modifiedAt))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let raw = try String(contentsOf: item.uri, encoding: .utf8)
        let parsed = parseFrontmatter(raw)
        let title = parsed.meta["title"] ?? firstHeading(in: parsed.body)
            ?? item.uri.deletingPathExtension().lastPathComponent

        var meta = parsed.meta
        let links = wikiLinks(in: parsed.body)
        if !links.isEmpty {
            meta["wikilinks"] = links.joined(separator: ",")
        }

        return ExtractedDocument(
            id: item.id,
            title: title,
            text: parsed.body,
            contentHash: ContentHash.of(parsed.body),
            meta: meta
        )
    }

    private func parseFrontmatter(_ raw: String) -> (meta: [String: String], body: String) {
        guard raw.hasPrefix("---\n") else {
            return ([:], raw)
        }

        let rest = raw.dropFirst(4)
        guard let close = rest.range(of: "\n---") else {
            return ([:], raw)
        }

        let block = rest[rest.startIndex..<close.lowerBound]
        var meta: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                meta[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        let body = String(rest[close.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (meta, body)
    }

    private func firstHeading(in body: String) -> String? {
        for line in body.split(separator: "\n") where line.hasPrefix("# ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func wikiLinks(in body: String) -> [String] {
        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.matches(in: body, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[swiftRange])
        }
    }
}
