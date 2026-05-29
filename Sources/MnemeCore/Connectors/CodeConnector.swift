import Foundation

public struct CodeConnector: SourceConnector {
    public let sourceId: String
    public let kind: SourceKind = .code
    private let root: URL
    private let ignoredDirs: Set<String>
    private let codeExtensions: Set<String>

    public init(
        root: URL,
        sourceId: String,
        ignoredDirs: Set<String> = [
            ".build", ".git", ".venv", "__pycache__", "DerivedData", "build",
            "dist", "node_modules", "outputs", "qdrant_storage"
        ],
        codeExtensions: Set<String> = [
            "c", "cpp", "go", "h", "hpp", "java", "js", "jsx", "kt", "m",
            "mm", "py", "rb", "rs", "sh", "swift", "toml", "ts", "tsx",
            "yaml", "yml"
        ]
    ) {
        self.root = root
        self.sourceId = sourceId
        self.ignoredDirs = ignoredDirs
        self.codeExtensions = codeExtensions
    }

    public func enumerate() throws -> [SourceItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [SourceItem] = []
        for case let url as URL in enumerator {
            if shouldIgnore(url) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard codeExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            items.append(SourceItem(id: url.absoluteString, uri: url, modifiedAt: modifiedAt))
        }
        return items.sorted { $0.id < $1.id }
    }

    public func extract(_ item: SourceItem) throws -> ExtractedDocument {
        let text = try String(contentsOf: item.uri, encoding: .utf8)
        let language = item.uri.pathExtension.lowercased()
        return ExtractedDocument(
            id: item.id,
            title: item.uri.lastPathComponent,
            text: text,
            contentHash: ContentHash.of(text),
            meta: ["language": language]
        )
    }

    private func shouldIgnore(_ url: URL) -> Bool {
        !Set(url.pathComponents).isDisjoint(with: ignoredDirs)
            || url.lastPathComponent.hasSuffix(".lock")
            || url.lastPathComponent == ".DS_Store"
    }
}
