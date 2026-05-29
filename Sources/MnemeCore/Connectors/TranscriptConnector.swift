import Foundation

public struct TranscriptConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .transcript
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
        for case let url as URL in enumerator where url.pathExtension == "json" {
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: modifiedAt))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(TranscriptDocument.self, from: Data(contentsOf: item.uri))
        let text = document.fullText
        var meta = [
            "model": document.model,
            "duration": String(document.duration)
        ]
        if let language = document.language {
            meta["language"] = language
        }
        if let sourceAudioPath = document.sourceAudioPath {
            meta["source_audio"] = sourceAudioPath
        }
        return ExtractedDocument(
            id: item.id,
            title: document.title,
            text: text,
            contentHash: ContentHash.of(text),
            meta: meta
        )
    }
}
