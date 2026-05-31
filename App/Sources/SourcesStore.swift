import Foundation
import MnemeCore

struct SourceConfig: Codable, Identifiable, Equatable {
    var id: String
    var kind: SourceKind
    var path: String
    var bookmarkData: Data?

    func resolvedURL() -> URL {
        guard let bookmarkData else {
            return URL(fileURLWithPath: path)
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        return URL(fileURLWithPath: path)
    }
}

@MainActor
final class SourcesStore: ObservableObject {
    @Published private(set) var sources: [SourceConfig] = []
    private let key = "mneme.sources.v1"

    init() {
        load()
    }

    func add(kind: SourceKind, url: URL) {
        let path = url.path
        guard !sources.contains(where: { $0.kind == kind && $0.path == path }) else {
            return
        }
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        sources.append(SourceConfig(
            id: UUID().uuidString,
            kind: kind,
            path: path,
            bookmarkData: bookmarkData
        ))
        save()
    }

    func add(kind: SourceKind, path: String) {
        add(kind: kind, url: URL(fileURLWithPath: path))
    }

    func remove(_ id: String) {
        sources.removeAll { $0.id == id }
        save()
    }

    func connectors() -> [any SourceConnector] {
        sources.map { config -> any SourceConnector in
            let url = config.resolvedURL()
            let connector: any SourceConnector
            switch config.kind {
            case .activity:
                connector = ActivityConnector(root: url, sourceId: config.id)
            case .pdf:
                connector = PDFConnector(root: url, sourceId: config.id)
            case .code:
                connector = CodeConnector(root: url, sourceId: config.id)
            case .transcript:
                connector = TranscriptConnector(root: url, sourceId: config.id)
            case .memory:
                connector = MemoryConnector(root: url, sourceId: config.id)
            case .agentSession:
                connector = AgentTranscriptConnector(root: url, sourceId: config.id)
            case .zotero:
                connector = ZoteroConnector(
                    libraryRoot: url,
                    sourceId: config.id,
                    cacheDir: Self.appSupportDir().appendingPathComponent("zotero-cache", isDirectory: true)
                )
            case .web:
                connector = WebClipConnector(root: url, sourceId: config.id)
            case .notes:
                connector = NotesConnector(root: url, sourceId: config.id)
            }
            if config.bookmarkData != nil {
                return SecurityScopedConnector(root: url, base: connector)
            }
            return connector
        }
    }

    func sourceURLs() -> [URL] {
        sources.map { config in
            config.resolvedURL()
        }
    }

    private func load() {
        let stores = [
            UserDefaults.standard,
            Self.crossProcessDefaults()
        ].compactMap { $0 }

        for store in stores {
            guard let data = store.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([SourceConfig].self, from: data) else {
                continue
            }
            sources = decoded
            return
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sources) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.synchronize()
        if let suite = Self.crossProcessDefaults() {
            suite.set(data, forKey: key)
            suite.synchronize()
        }
    }

    private static func appSupportDir() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Mneme", isDirectory: true)
    }

    private static func crossProcessDefaults() -> UserDefaults? {
        guard Bundle.main.bundleIdentifier != SourcesReader.packagedAppDefaultsSuite else {
            return nil
        }
        return UserDefaults(suiteName: SourcesReader.packagedAppDefaultsSuite)
    }
}

private struct SecurityScopedConnector: SourceConnector {
    let root: URL
    let base: any SourceConnector

    var sourceId: String { base.sourceId }
    var kind: SourceKind { base.kind }

    func enumerate() throws -> [SourceItem] {
        try withSecurityScope {
            try base.enumerate()
        }
    }

    func extract(_ item: SourceItem) throws -> ExtractedDocument {
        try withSecurityScope {
            try base.extract(item)
        }
    }

    private func withSecurityScope<T>(_ work: () throws -> T) rethrows -> T {
        let didStart = root.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                root.stopAccessingSecurityScopedResource()
            }
        }
        return try work()
    }
}
