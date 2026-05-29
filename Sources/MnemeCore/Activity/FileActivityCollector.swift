import Foundation

public struct FileActivityCollector: Sendable {
    private let ignoreRules: ActivityIgnoreRules

    public init(ignoreRules: ActivityIgnoreRules = .default) {
        self.ignoreRules = ignoreRules
    }

    public func collect(root: URL, since: Date) throws -> [FileTouch] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var touches: [FileTouch] = []
        for case let url as URL in enumerator {
            let relativePath = Self.relativePath(for: url, root: root)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])

            if values.isDirectory == true {
                if ignoreRules.shouldIgnore(relativePath: relativePath) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard !ignoreRules.shouldIgnore(relativePath: relativePath),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= since else {
                continue
            }

            touches.append(FileTouch(
                relativePath: relativePath,
                touchCount: 1,
                lastModifiedAt: modifiedAt
            ))
        }

        return touches.sorted { lhs, rhs in
            if lhs.lastModifiedAt == rhs.lastModifiedAt {
                return lhs.relativePath < rhs.relativePath
            }
            return lhs.relativePath < rhs.relativePath
        }
    }

    static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
}
