import Foundation

public struct ActivityConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .activity
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
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: modifiedAt))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let raw = try String(contentsOf: item.uri, encoding: .utf8)
        let text = managedBlock(in: raw) ?? raw
        let date = item.uri.deletingPathExtension().lastPathComponent
        return ExtractedDocument(
            id: item.id,
            title: "Activity \(date)",
            text: text,
            contentHash: ContentHash.of(text),
            meta: ["date": date]
        )
    }

    private func managedBlock(in text: String) -> String? {
        guard let start = text.range(of: DailyActivityRenderer.startMarker),
              let end = text.range(of: DailyActivityRenderer.endMarker, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.lowerBound..<end.upperBound])
    }
}
