import Foundation

public struct ActivityIgnoreRules: Equatable, Sendable {
    public let ignoredPathComponents: Set<String>
    public let ignoredFilenames: Set<String>
    public let ignoredSuffixes: Set<String>

    public static let `default` = ActivityIgnoreRules(
        ignoredPathComponents: [
            ".build", ".git", ".obsidian", ".trash", ".venv", "__pycache__",
            "DerivedData", "build", "dist", "node_modules", "outputs",
            "qdrant_storage"
        ],
        ignoredFilenames: [".DS_Store"],
        ignoredSuffixes: [".lock", ".swp", ".tmp"]
    )

    public init(
        ignoredPathComponents: Set<String>,
        ignoredFilenames: Set<String>,
        ignoredSuffixes: Set<String>
    ) {
        self.ignoredPathComponents = ignoredPathComponents
        self.ignoredFilenames = ignoredFilenames
        self.ignoredSuffixes = ignoredSuffixes
    }

    public func shouldIgnore(relativePath: String) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard let filename = components.last else { return false }

        if components.contains(where: ignoredPathComponents.contains) {
            return true
        }
        if ignoredFilenames.contains(filename) {
            return true
        }
        return ignoredSuffixes.contains { filename.hasSuffix($0) }
    }
}
