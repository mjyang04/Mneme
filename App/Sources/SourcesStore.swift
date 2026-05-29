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
        sources.map { config in
            let url = config.resolvedURL()
            _ = url.startAccessingSecurityScopedResource()
            switch config.kind {
            case .activity:
                return ActivityConnector(root: url, sourceId: config.id)
            case .pdf:
                return PDFConnector(root: url, sourceId: config.id)
            case .code:
                return CodeConnector(root: url, sourceId: config.id)
            case .transcript:
                return TranscriptConnector(root: url, sourceId: config.id)
            case .notes:
                return NotesConnector(root: url, sourceId: config.id)
            }
        }
    }

    func sourceURLs() -> [URL] {
        sources.map { config in
            let url = config.resolvedURL()
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SourceConfig].self, from: data) else {
            return
        }
        sources = decoded
    }

    private func save() {
        let data = try? JSONEncoder().encode(sources)
        UserDefaults.standard.set(data, forKey: key)
    }
}
