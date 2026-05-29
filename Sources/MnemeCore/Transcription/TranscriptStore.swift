import Foundation

public struct TranscriptStore: Sendable {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ document: TranscriptDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: url(for: document.id), options: .atomic)
    }

    public func load(id: String) throws -> TranscriptDocument {
        let data = try Data(contentsOf: url(for: id))
        return try decoder.decode(TranscriptDocument.self, from: data)
    }

    public func list() throws -> [TranscriptDocument] {
        guard let urls = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var documents: [TranscriptDocument] = []
        for case let url as URL in urls where url.pathExtension == "json" {
            if let document = try? decoder.decode(TranscriptDocument.self, from: Data(contentsOf: url)) {
                documents.append(document)
            }
        }
        return documents.sorted { $0.createdAt < $1.createdAt }
    }

    public func url(for id: String) -> URL {
        directory.appendingPathComponent("\(safeFilename(id)).json")
    }

    private func safeFilename(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
