import Foundation

public struct ActivityFileEvent: Hashable, Sendable {
    public let workspaceRoot: URL
    public let relativePath: String

    public init(workspaceRoot: URL, relativePath: String) {
        self.workspaceRoot = workspaceRoot
        self.relativePath = relativePath
    }
}

public final class ActivityEventBatcher: @unchecked Sendable {
    private let workspaceRoots: [URL]
    private let ignoreRules: ActivityIgnoreRules
    private let lock = NSLock()
    private var pending = Set<ActivityFileEvent>()

    public init(workspaceRoots: [URL], ignoreRules: ActivityIgnoreRules = .default) {
        self.workspaceRoots = workspaceRoots.map(\.standardizedFileURL)
        self.ignoreRules = ignoreRules
    }

    @discardableResult
    public func record(_ url: URL) -> Bool {
        guard let event = event(for: url.standardizedFileURL) else { return false }
        lock.withLock {
            _ = pending.insert(event)
        }
        return true
    }

    public func drain() -> [ActivityFileEvent] {
        lock.withLock {
            let events = Array(pending).sorted {
                if $0.workspaceRoot.path == $1.workspaceRoot.path {
                    return $0.relativePath < $1.relativePath
                }
                return $0.workspaceRoot.path < $1.workspaceRoot.path
            }
            pending.removeAll()
            return events
        }
    }

    private func event(for url: URL) -> ActivityFileEvent? {
        for root in workspaceRoots {
            let rootPath = root.path
            let filePath = url.path
            guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else {
                continue
            }
            let relative = FileActivityCollector.relativePath(for: url, root: root)
            guard !relative.isEmpty, !ignoreRules.shouldIgnore(relativePath: relative) else {
                return nil
            }
            return ActivityFileEvent(workspaceRoot: root, relativePath: relative)
        }
        return nil
    }
}
