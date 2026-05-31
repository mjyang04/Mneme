import Foundation

public struct PDFConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .pdf
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
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "pdf" {
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: modifiedAt))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let extraction = try PDFTextExtractor.extract(url: item.uri)
        return ExtractedDocument(
            id: item.id,
            title: extraction.title ?? item.uri.deletingPathExtension().lastPathComponent,
            text: extraction.text,
            contentHash: ContentHash.of(extraction.text),
            meta: ["pages": String(extraction.pageCount)]
        )
    }
}
