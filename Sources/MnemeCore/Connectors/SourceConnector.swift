import Foundation

public protocol SourceConnector: Sendable {
    var sourceId: String { get }
    var kind: SourceKind { get }

    func enumerate() throws -> [SourceItem]
    func extract(_ item: SourceItem) throws -> ExtractedDocument
}
