import Foundation

public struct MnemeSourceConfig: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SourceKind
    public let path: String
    public let bookmarkData: Data?

    public init(id: String, kind: SourceKind, path: String, bookmarkData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.path = path
        self.bookmarkData = bookmarkData
    }
}

public struct SourcesReader: Sendable {
    public static let defaultKey = "mneme.sources.v1"
    public static let packagedAppDefaultsSuite = "local.mneme.app"

    private let key: String
    private let defaultsSuites: [String]

    public init(
        key: String = Self.defaultKey,
        defaultsSuites: [String] = [Self.packagedAppDefaultsSuite]
    ) {
        self.key = key
        self.defaultsSuites = defaultsSuites
    }

    public func load() -> [MnemeSourceConfig] {
        for data in candidateData() {
            if let decoded = try? JSONDecoder().decode([MnemeSourceConfig].self, from: data) {
                return decoded
            }
        }
        return []
    }

    private func candidateData() -> [Data] {
        var values: [Data] = []
        if let data = UserDefaults.standard.data(forKey: key) {
            values.append(data)
        }
        for suite in defaultsSuites {
            if let data = UserDefaults(suiteName: suite)?.data(forKey: key) {
                values.append(data)
            }
        }
        return values
    }
}
